# frozen_string_literal: true

module TermElectives
  # Reads the Registrar's elective page and imports each PDF it links into a
  # TermElectiveList. A PDF with the same digest as the last import is not
  # downloaded into pdftotext again: its stored text is parsed again, and its
  # courses are written again only when they differ, such as after Banner
  # adds a subject. A changed PDF has its courses written again.
  #
  # The page is the source of truth for each term it links. A list of such a
  # term whose URL left the page, such as "FA26 HSS Electives V2.pdf" after
  # V3 came out, is deleted. A term the page no longer links keeps its lists.
  class Importer
    Result = Data.define(:imported, :unchanged, :skipped, :failed, :removed)

    def initialize(client: RegistrarClient.new)
      @client = client
    end

    def call
      @known_subjects = nil
      page = @client.get(PAGE_URL)
      raise FetchError, "GET #{PAGE_URL}: not found" if page.nil?

      urls = pdf_urls(page)
      counts = Hash.new(0)
      term_ids = urls.filter_map { |url| import(url, counts) }

      counts[:removed] = TermElectiveList.where(term_id: term_ids.uniq).where.not(url: urls).destroy_all.size
      # A course that Banner added since the last import gets its link.
      TermElectiveCourse.link_catalog_courses
      Result.new(**Result.members.index_with { |key| counts[key] })
    end

    private

    # Returns the term id of the list, or nil when the file was not stored.
    def import(url, counts)
      pdf = @client.get(url)
      if pdf.nil?
        counts[:skipped] += 1
        return
      end

      sha256 = Digest::SHA256.hexdigest(pdf)
      list = TermElectiveList.find_by(url: url)
      if list&.sha256 == sha256
        parsed = PdfParser.parse(list.body_text)
        write_courses(list, parsed) unless rows(parsed) == stored_rows(list)
        counts[:unchanged] += 1
        return list.term_id
      end

      # Postgres refuses a NUL byte in a text column.
      text = FinalsSchedules::PdfText.extract(pdf).scrub.delete("\0")
      parsed = PdfParser.parse(text)
      term = Term.find_by(year: parsed.year, season: parsed.season) if parsed.year
      if term.nil?
        Rails.logger.warn("[TermElectives] no term for #{url} (#{parsed.season} #{parsed.year})")
        counts[:skipped] += 1
        return
      end

      write(list || TermElectiveList.new(url: url), term, sha256, text, parsed)
      counts[:imported] += 1
      term.id
    rescue FetchError, RuntimeError, ArgumentError, ActiveRecord::ActiveRecordError => e
      # One bad file does not stop the others. The next run tries it again.
      Rails.error.report(e, handled: true, context: { url: url })
      counts[:failed] += 1
      nil
    end

    def write(list, term, sha256, text, parsed)
      TermElectiveList.transaction do
        list.update!(term: term, school: school(list.url), title: parsed.title, sha256: sha256,
                     body_text: text, fetched_at: Time.current)
        write_courses(list, parsed)
      end
    end

    def write_courses(list, parsed)
      TermElectiveList.transaction do
        list.courses.delete_all
        new_rows = rows(parsed).map { |row| row.merge(term_elective_list_id: list.id) }
        TermElectiveCourse.insert_all!(new_rows) if new_rows.any?
        TermElectiveCourse.where(term_elective_list: list).link_catalog_courses
      end
    end

    # A code such as "FALL 2026" looks like a course code. Only subjects
    # that Banner knows are kept.
    def rows(parsed)
      parsed.courses
            .select { |course| known_subjects.include?(course.subject_code) }
            .each_with_index
            .map { |course, position| course.to_h.merge(position: position) }
    end

    def stored_rows(list)
      list.courses.pluck(:subject_code, :course_number, :heading, :position)
          .map { |subject_code, course_number, heading, position| { subject_code:, course_number:, heading:, position: } }
    end

    # Links to PDFs on wit.edu over HTTPS. A link can have a raw space, such
    # as "FA26 HSS Electives V3.pdf", so the href is escaped first.
    def pdf_urls(page)
      Nokogiri::HTML(page).css("a[href]").filter_map do |link|
        href = link["href"].strip.gsub(" ", "%20")
        uri = URI.join(PAGE_URL, href)
        next unless uri.path.to_s.match?(/\.pdf\z/i)
        next uri.to_s if uri.scheme == "https" && uri.host.to_s.downcase.delete_prefix("www.") == SITE_HOST

        Rails.logger.warn("[TermElectives] skipped PDF link #{href}")
        nil
      rescue URI::Error
        Rails.logger.warn("[TermElectives] skipped PDF link #{href}")
        nil
      end.uniq
    end

    def known_subjects
      @known_subjects ||= CatalogCourse.distinct.pluck(:subject_code).to_set
    end

    def school(url)
      name = CGI.unescape(File.basename(URI(url).path)).upcase
      SCHOOLS.find { |code| name.match?(/(?<![A-Z])#{code}(?![A-Z])/) }
    end
  end
end

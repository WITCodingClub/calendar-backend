# frozen_string_literal: true

module TermElectives
  # Reads the Registrar's elective page and imports each PDF it links into a
  # TermElectiveList. A PDF with the same digest as the last import is
  # skipped. A changed PDF has its courses written again.
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
      page = @client.get(PAGE_URL)
      raise FetchError, "GET #{PAGE_URL}: not found" if page.nil?

      urls = pdf_urls(page)
      counts = Hash.new(0)
      term_ids = urls.filter_map { |url| import(url, counts) }

      counts[:removed] = TermElectiveList.where(term_id: term_ids.uniq).where.not(url: urls).destroy_all.size
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
        counts[:unchanged] += 1
        return list.term_id
      end

      text = FinalsSchedules::PdfText.extract(pdf).scrub
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
    rescue FetchError, RuntimeError => e
      # One bad file does not stop the others. The next run tries it again.
      Rails.error.report(e, handled: true, context: { url: url })
      counts[:failed] += 1
      nil
    end

    def write(list, term, sha256, text, parsed)
      rows = parsed.courses
                   .select { |course| known_subjects.include?(course.subject_code) }
                   .each_with_index
                   .map { |course, position| course.to_h.merge(position: position) }

      TermElectiveList.transaction do
        list.update!(term: term, school: school(list.url), title: parsed.title, sha256: sha256,
                     body_text: text, fetched_at: Time.current)
        list.courses.delete_all
        TermElectiveCourse.insert_all!(rows.map { |row| row.merge(term_elective_list_id: list.id) }) if rows.any?
        TermElectiveCourse.where(term_elective_list: list).link_catalog_courses
      end
    end

    def pdf_urls(page)
      Nokogiri::HTML(page).css("a[href]").filter_map do |link|
        url = URI.join(PAGE_URL, link["href"].strip).to_s
        url if URI(url).host == URI(PAGE_URL).host && url.match?(/\.pdf\z/i)
      rescue URI::Error
        nil
      end.uniq
    end

    # A code such as "FALL 2026" looks like a course code. Only subjects
    # that Banner knows are kept.
    def known_subjects
      @known_subjects ||= CatalogCourse.distinct.pluck(:subject_code).to_set
    end

    def school(url)
      name = CGI.unescape(File.basename(URI(url).path)).upcase
      SCHOOLS.find { |code| name.match?(/(?<![A-Z])#{code}(?![A-Z])/) }
    end
  end
end

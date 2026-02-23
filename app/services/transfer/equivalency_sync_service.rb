# frozen_string_literal: true

module Transfer
  class EquivalencySyncService < ApplicationService
    require "faraday"
    require "nokogiri"

    TES_BASE_URL = "https://tes.collegesource.com/publicview/TES_publicview01.aspx"
    TES_RID = "ff2d54be-fd79-43ae-ab65-0de2a31cad80"
    USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"

    def call
      @results = { universities_synced: 0, courses_synced: 0, equivalencies_synced: 0, errors: [] }

      Rails.logger.info "[TransferEquivalencySync] Starting sync from TES database"

      begin
        html = fetch_tes_page
        equivalencies_data = parse_equivalencies(html)

        if equivalencies_data.empty?
          Rails.logger.warn "[TransferEquivalencySync] No equivalency data found on TES page"
          @results[:errors] << "No equivalency data found - the TES page may require interactive session"
          return @results
        end

        process_equivalencies(equivalencies_data)
      rescue Faraday::Error => e
        @results[:errors] << "Network error: #{e.message}"
        Rails.logger.error "[TransferEquivalencySync] Network error: #{e.message}"
      rescue => e
        @results[:errors] << "Unexpected error: #{e.message}"
        Rails.logger.error "[TransferEquivalencySync] Unexpected error: #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")
      end

      Rails.logger.info "[TransferEquivalencySync] Completed: #{@results.except(:errors).inspect}"
      @results
    end

    private

    def fetch_tes_page
      response = connection.get(TES_BASE_URL, rid: TES_RID)

      unless response.success?
        raise "TES page returned HTTP #{response.status}"
      end

      response.body
    end

    # Parse the equivalency grid from the TES page HTML.
    # The TES page uses a GridView with id="gdvCourseEQ" containing equivalency rows.
    # Each row has columns: checkbox, sending institution + course, receiving course, dates.
    #
    # If the main grid is not present (page says "not available" or requires postback),
    # we fall back to parsing any available equivalency data from the page.
    def parse_equivalencies(html)
      doc = Nokogiri::HTML(html)
      equivalencies = []

      # Try the main equivalency grid
      grid = doc.at_css("#gdvCourseEQ")
      if grid
        rows = grid.css("tr").drop(1) # skip header row
        rows.each do |row|
          data = parse_grid_row(row)
          equivalencies << data if data
        end
        return equivalencies
      end

      # The TES page is an ASP.NET WebForms application that requires interactive
      # postbacks to load equivalency data. If the grid is not found, attempt to
      # perform a search postback to load data.
      fetch_via_postback(doc)

    end

    def parse_grid_row(row)
      cells = row.css("td")
      return nil if cells.size < 4

      # Typical TES grid columns:
      # [checkbox] [sending institution + course info] [receiving/equivalent course] [dates/status]
      sending_cell = cells[1]
      receiving_cell = cells[2]

      return nil unless sending_cell && receiving_cell

      sending_info = parse_course_cell(sending_cell)
      receiving_info = parse_course_cell(receiving_cell)

      return nil unless sending_info && receiving_info

      {
        sending_institution: sending_info[:institution],
        sending_course_code: sending_info[:course_code],
        sending_course_title: sending_info[:course_title],
        sending_credits: sending_info[:credits],
        wit_course_code: receiving_info[:course_code],
        wit_course_title: receiving_info[:course_title],
        effective_date: parse_date_from_row(cells),
        expiration_date: parse_expiration_from_row(cells)
      }
    end

    def parse_course_cell(cell)
      text = cell.text.strip
      return nil if text.blank?

      lines = text.split("\n").map(&:strip).compact_blank
      return nil if lines.empty?

      institution = nil
      course_code = nil
      course_title = nil
      credits = nil

      # Look for institution name (usually bold or in a span with class)
      inst_el = cell.at_css(".institution_name, b, strong")
      institution = inst_el&.text&.strip

      # Parse course code and title from remaining text
      lines.each do |line|
        next if line == institution

        if line.match?(/\A[A-Z]{2,6}\s*\d{3,4}/)
          course_code = line
        elsif line.match?(/\d+(\.\d+)?\s*credits?/i)
          credits = line[/(\d+(?:\.\d+)?)/, 1]&.to_f
        elsif course_code && course_title.nil?
          course_title = line
        end
      end

      # If we didn't find structured data, try a simpler parse
      if course_code.nil? && lines.size >= 2
        course_code = lines.first
        course_title = lines[1] if lines.size > 1
      end

      return nil if course_code.blank?

      {
        institution: institution,
        course_code: course_code,
        course_title: course_title || course_code,
        credits: credits
      }
    end

    def parse_date_from_row(cells)
      cells.each do |cell|
        text = cell.text.strip
        date = extract_date(text)
        return date if date
      end
      nil
    end

    def parse_expiration_from_row(cells)
      dates = []
      cells.each do |cell|
        text = cell.text.strip
        date = extract_date(text)
        dates << date if date
      end
      # Second date is typically the expiration
      dates.size >= 2 ? dates[1] : nil
    end

    def extract_date(text)
      if text.match?(/\d{1,2}\/\d{1,2}\/\d{4}/)
        Date.strptime(text[/(\d{1,2}\/\d{1,2}\/\d{4})/, 1], "%m/%d/%Y")
      end
    rescue Date::Error
      nil
    end

    def fetch_via_postback(doc)
      # Extract ASP.NET form fields needed for postback
      vstate = doc.at_css("#_VSTATE")&.[]("value")
      viewstate = doc.at_css("#__VIEWSTATE")&.[]("value")
      event_validation = doc.at_css("#__EVENTVALIDATION")&.[]("value")

      return [] unless event_validation

      # Perform a search postback to load all institutions' equivalencies
      form_data = {
        "_VSTATE"           => vstate.to_s,
        "__VIEWSTATE"       => viewstate.to_s,
        "__EVENTVALIDATION" => event_validation,
        "__EVENTTARGET"     => "btnCourseEQSearch",
        "__EVENTARGUMENT"   => "",
        "rblEffectiveDate"  => "3", # Both active and inactive
        "tbxCourseCode"     => "",
        "rblCourseCodeType" => "3", # Both transfer and equivalent
        "ddlRecordsPerPage" => "200",
        "ddlSortListBy"     => "1"
      }

      response = connection.post("#{TES_BASE_URL}?rid=#{TES_RID}") do |req|
        req.headers["Content-Type"] = "application/x-www-form-urlencoded"
        req.body = URI.encode_www_form(form_data)
      end

      return [] unless response.success?

      result_doc = Nokogiri::HTML(response.body)
      grid = result_doc.at_css("#gdvCourseEQ")
      return [] unless grid

      equivalencies = []
      rows = grid.css("tr").drop(1)
      rows.each do |row|
        data = parse_grid_row(row)
        equivalencies << data if data
      end

      equivalencies
    end

    def process_equivalencies(equivalencies_data)
      equivalencies_data.each do |data|
        process_single_equivalency(data)
      rescue => e
        @results[:errors] << "Error processing #{data[:sending_course_code]}: #{e.message}"
        Rails.logger.error "[TransferEquivalencySync] Error processing equivalency: #{e.message}"
      end
    end

    def process_single_equivalency(data)
      return if data[:sending_institution].blank?

      university = find_or_create_university(data[:sending_institution])
      return unless university

      transfer_course = find_or_create_transfer_course(university, data)
      return unless transfer_course

      wit_course = find_wit_course(data[:wit_course_code])
      unless wit_course
        @results[:errors] << "WIT course not found for: #{data[:wit_course_code]}"
        return
      end

      find_or_create_equivalency(transfer_course, wit_course, data)
    end

    def find_or_create_university(institution_name)
      code = generate_university_code(institution_name)

      university = Transfer::University.find_or_initialize_by(code: code)
      if university.new_record?
        university.name = institution_name
        university.active = true
        university.save!
        @results[:universities_synced] += 1
        Rails.logger.info "[TransferEquivalencySync] Created university: #{institution_name} (#{code})"
      end

      university
    rescue ActiveRecord::RecordInvalid => e
      @results[:errors] << "Failed to create university #{institution_name}: #{e.message}"
      nil
    end

    def find_or_create_transfer_course(university, data)
      course = Transfer::Course.find_or_initialize_by(
        university: university,
        course_code: data[:sending_course_code]
      )

      if course.new_record?
        course.course_title = data[:sending_course_title] || data[:sending_course_code]
        course.credits = data[:sending_credits]
        course.active = true
        course.save!
        @results[:courses_synced] += 1
      end

      course
    rescue ActiveRecord::RecordInvalid => e
      @results[:errors] << "Failed to create transfer course #{data[:sending_course_code]}: #{e.message}"
      nil
    end

    def find_wit_course(course_code)
      return nil if course_code.blank?

      # Parse subject and course number from code like "COMP 1000" or "COMP1000"
      match = course_code.match(/\A([A-Z]+)\s*(\d+)\z/)
      return nil unless match

      subject_prefix = match[1]
      course_number = match[2].to_i

      # WIT courses store subject as full name with abbreviation in parens, e.g. "Computer Science (COMP)"
      # Match by the abbreviation in parens and course_number
      Course.where(course_number: course_number)
            .where("subject LIKE ?", "%(#{subject_prefix})%")
            .order(created_at: :desc)
            .first
    end

    def find_or_create_equivalency(transfer_course, wit_course, data)
      equivalency = Transfer::Equivalency.find_or_initialize_by(
        transfer_course: transfer_course,
        wit_course: wit_course
      )

      if equivalency.new_record?
        equivalency.effective_date = data[:effective_date] || Date.current
        equivalency.expiration_date = data[:expiration_date]
        equivalency.save!
        @results[:equivalencies_synced] += 1
      end

      equivalency
    rescue ActiveRecord::RecordInvalid => e
      @results[:errors] << "Failed to create equivalency: #{e.message}"
      nil
    end

    def generate_university_code(name)
      # Generate a short code from the institution name
      # e.g. "Boston University" -> "BOSTON-UNIV"
      words = name.gsub(/[^a-zA-Z\s]/, "").split
      if words.size <= 2
        words.map { |w| w.upcase[0..5] }.join("-")
      else
        "#{words.first(3).map { |w| w[0].upcase }.join}-#{words.first.upcase[0..3]}"
      end
    end

    def connection
      @connection ||= Faraday.new do |faraday|
        faraday.headers["User-Agent"] = USER_AGENT
        faraday.headers["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
        faraday.request :url_encoded
        faraday.adapter Faraday.default_adapter
        faraday.options.timeout = 30
        faraday.options.open_timeout = 10
      end
    end

  end
end

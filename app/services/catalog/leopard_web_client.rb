# frozen_string_literal: true

module Catalog
  class LeopardWebClient < ApplicationService
    require "faraday"
    require "nokogiri"

    BASE_URL = "https://selfservice.wit.edu/StudentRegistrationSsb/ssb/searchResults/"

    class RequestError < StandardError
      attr_reader :status
      def initialize(msg, status: nil)
        @status = status
        super(msg)
      end
    end

    class SessionError < StandardError; end
    class ParseError < StandardError; end

    OPEN_TIMEOUT = 10
    READ_TIMEOUT = 30

    attr_reader :term, :course_reference_number, :action

    def initialize(action:, term: nil, course_reference_number: nil)
      @action = action
      @term = term
      @course_reference_number = course_reference_number
      super()
    end

    def call
      case action
      when :get_class_details
        get_class_details
      when :get_enrollment_info
        get_enrollment_info
      when :get_faculty_meeting_times
        get_faculty_meeting_times
      when :get_course_catalog
        get_course_catalog
      when :get_active_terms
        get_active_terms
      when :fetch_linked_sections
        fetch_linked_sections
      else
        raise ArgumentError, "Unknown action: #{action}"
      end
    end

    def call!
      call
    end

    def self.get_class_details(term:, course_reference_number:)
      new(
        action: :get_class_details,
        term: term,
        course_reference_number: course_reference_number
      ).call
    end

    def self.get_enrollment_info(term:, course_reference_number:)
      new(
        action: :get_enrollment_info,
        term: term,
        course_reference_number: course_reference_number
      ).call
    end

    def self.get_faculty_meeting_times(term:, course_reference_number:)
      new(
        action: :get_faculty_meeting_times,
        term: term,
        course_reference_number: course_reference_number
      ).call
    end

    # Banner's lecture and lab pairs for one section, as option groups: the
    # section can be taken with any one group, and every section in that group
    # is needed. An unlinked section returns []. Each entry is
    # { crn: Integer, credit_hours: Integer or nil }; Banner gives a lab 0
    # credit hours here.
    def self.fetch_linked_sections(term:, course_reference_number:)
      new(
        action: :fetch_linked_sections,
        term: term,
        course_reference_number: course_reference_number
      ).call
    end

    def self.get_course_catalog(term:)
      new(
        action: :get_course_catalog,
        term: term
      ).call
    end

    # The four pages Banner shows for a section's course: the description, the
    # prerequisites, the corequisites, and the restrictions. Each is HTML, which
    # Catalog::CourseDetailsParser reads. Raises RequestError when Banner does
    # not answer 200.
    COURSE_DETAIL_PAGES = {
      description:   "getCourseDescription",
      prerequisites: "getSectionPrerequisites",
      corequisites:  "getCorequisites",
      restrictions:  "getRestrictions"
    }.freeze

    # @return [Hash{Symbol => String}] the HTML of each page in COURSE_DETAIL_PAGES
    def self.get_course_details(term:, course_reference_number:)
      new(action: :get_course_details, term: term, course_reference_number: course_reference_number).course_details
    end

    # The requests go one after another, not at once, so a sync of every
    # course in a term stays gentle on Banner.
    def course_details
      raise ArgumentError, "term is required" unless term
      raise ArgumentError, "course_reference_number is required" unless course_reference_number

      COURSE_DETAIL_PAGES.transform_values do |path|
        response = connection.get(path, { term: term, courseReferenceNumber: course_reference_number })
        raise RequestError.new("Banner #{path} answered #{response.status}", status: response.status) unless response.status == 200

        response.body.to_s
      end
    end

    ACTIVE_TERMS_CACHE_KEY = "leopard_web/active_terms"

    # Banner's term list changes a few times a year. The admin catalog page and
    # Term#registration_start ask for it on each call, and the request can take
    # up to 30 seconds, so keep a good answer for ten minutes. A failed answer is
    # not kept.
    def self.get_active_terms
      cached = Rails.cache.read(ACTIVE_TERMS_CACHE_KEY)
      return cached if cached

      result = new(action: :get_active_terms).call
      Rails.cache.write(ACTIVE_TERMS_CACHE_KEY, result, expires_in: 10.minutes) if result[:success]
      result
    end

    private

    def fetch_linked_sections
      raise ArgumentError, "term is required" unless term
      raise ArgumentError, "course_reference_number is required" unless course_reference_number

      response = connection.get("fetchLinkedSections", { term: term, courseReferenceNumber: course_reference_number })
      data = handle_response(response, :json)
      groups = data.is_a?(Hash) ? data["linkedData"] : nil
      raise ParseError, "fetchLinkedSections returned no linkedData" unless groups.is_a?(Array)

      groups.map do |group|
        Array(group).filter_map do |section|
          crn = section["courseReferenceNumber"].to_s
          next unless crn.match?(/\A\d+\z/)

          { crn: crn.to_i, credit_hours: section["creditHours"]&.to_i }
        end
      end.reject(&:empty?)
    end

    def get_class_details
      raise ArgumentError, "term is required" unless term
      raise ArgumentError, "course_reference_number is required" unless course_reference_number

      # Banner gives the details, the meeting times, and the seats on three
      # separate requests. Send them together, not one after another. The
      # results are still read in the old order, so a failed request or a
      # missing section has the same effect as before.
      connection
      response, meeting_times_attempt, enrollment_attempt = Concurrently.map(
        [
          -> { connection.get("getClassDetails", { term: term, courseReferenceNumber: course_reference_number }) },
          -> { attempt { get_faculty_meeting_times } },
          -> { attempt { get_enrollment_info } }
        ],
        &:call
      )

      details = handle_response(response, :class_details)
      return nil unless details

      meeting_times_data = meeting_times_attempt.value!

      if meeting_times_data.present? && meeting_times_data["fmt"].present?
        details[:meeting_times] = meeting_times_data["fmt"].map do |mt_data|
          mt = mt_data["meetingTime"]
          next if mt.nil?

          {
            "building"             => mt["building"],
            "building_description" => mt["buildingDescription"],
            "campus"               => mt["campus"],
            "campus_description"   => mt["campusDescription"],
            "room"                 => mt["room"],
            "startDate"            => mt["startDate"],
            "endDate"              => mt["endDate"],
            "startTime"            => mt["beginTime"],
            "endTime"              => mt["endTime"],
            "days"                 => {
              "monday"    => mt["monday"],
              "tuesday"   => mt["tuesday"],
              "wednesday" => mt["wednesday"],
              "thursday"  => mt["thursday"],
              "friday"    => mt["friday"],
              "saturday"  => mt["saturday"],
              "sunday"    => mt["sunday"]
            }
          }
        end.compact

        details[:faculty] = extract_faculty(meeting_times_data["fmt"])
      end

      begin
        enrollment_data = enrollment_attempt.value!
        if enrollment_data
          details[:seats_available] = enrollment_data.dig(:enrollment, :seats_available)
          details[:seats_capacity]  = enrollment_data.dig(:enrollment, :maximum)
          details[:waitlist_available] = enrollment_data.dig(:waitlist, :seats_available)
          details[:waitlist_capacity]  = enrollment_data.dig(:waitlist, :capacity)
        end
      rescue => e
        Rails.error.report(e, handled: true, context: { crn: course_reference_number, term: term })
      end

      details
    end

    # Banner needs the term and the CRN to know which section to describe, and it
    # only answers this one over POST. Without them it returns a page with no
    # enrollment section at all, the parser returns nil, and the seat columns are
    # never written.
    def get_enrollment_info
      raise ArgumentError, "term is required" unless term
      raise ArgumentError, "course_reference_number is required" unless course_reference_number

      response = connection.post("getEnrollmentInfo", {
                                   term: term,
                                   courseReferenceNumber: course_reference_number
                                 })

      handle_response(response, :enrollment_info)
    end

    # getFacultyMeetingTimes answers with the section's instructors alongside its
    # meeting times, and Banner is the only place that says who actually teaches a
    # section. Reading just the meeting times left us guessing from whatever the
    # extension happened to post, so a mid-semester instructor change never
    # reached the calendar.
    def extract_faculty(fmt_entries)
      fmt_entries.flat_map { |entry| entry["faculty"] || [] }
                 .filter_map do |member|
                   email = member["emailAddress"].to_s.strip
                   next if email.blank?

                   {
                     "displayName"      => member["displayName"].to_s.strip,
                     "emailAddress"     => email,
                     "primaryIndicator" => ActiveModel::Type::Boolean.new.cast(member["primaryIndicator"]) || false
                   }
                 end
                 .uniq { |member| member["emailAddress"].downcase }
    end

    # The result of a request that ran in another thread. value! gives the result
    # or raises the request's error, at the point the caller reads it.
    Attempt = Struct.new(:value, :error) do
      def value!
        raise error if error

        value
      end
    end

    def attempt
      Attempt.new(yield, nil)
    rescue StandardError => e
      Attempt.new(nil, e)
    end

    def get_faculty_meeting_times
      raise ArgumentError, "term is required" unless term
      raise ArgumentError, "course_reference_number is required" unless course_reference_number

      response = connection.get("getFacultyMeetingTimes", {
                                  term: term,
                                  courseReferenceNumber: course_reference_number
                                })

      handle_response(response, :json)
    end

    def connection
      @connection ||= Faraday.new(url: BASE_URL) do |faraday|
        faraday.options.open_timeout = OPEN_TIMEOUT
        faraday.options.timeout = READ_TIMEOUT
        faraday.request :url_encoded
        # Pacing, retries, and the cooldown for every Banner request.
        faraday.use Catalog::BannerThrottle
        faraday.response :json, content_type: /\bjson$/
        faraday.adapter Faraday.default_adapter
      end
    end

    def handle_response(response, format = :json)
      if response.success?
        case format
        when :class_details
          parse_class_details_html(response.body)
        when :enrollment_info
          parse_enrollment_info_html(response.body)
        when :json
          parse_json_response(response.body)
        else
          parse_response_body(response.body)
        end
      else
        handle_error(response)
      end
    end

    def parse_response_body(body)
      body
    end

    def parse_json_response(body)
      body.is_a?(String) ? JSON.parse(body) : body
    end

    def parse_class_details_html(html)
      doc = Nokogiri::HTML(html)
      section = doc.at_css('section[aria-labelledby="classDetails"]')

      return nil unless section

      {
        associated_term: extract_labeled_value(section, "Associated Term:"),
        crn: section.at_css("#courseReferenceNumber")&.text&.strip,
        campus: extract_labeled_value(section, "Campus:"),
        schedule_type: extract_labeled_value(section, "Schedule Type:"),
        section_number: section.at_css("#sectionNumber")&.text&.strip,
        subject: section.at_css("#subject")&.text&.strip,
        course_number: section.at_css("#courseNumber")&.text&.strip,
        title: section.at_css("#courseTitle")&.text&.strip,
        credit_hours: extract_labeled_value(section, "Credit Hours:")&.to_i,
        grade_mode: extract_labeled_value(section, "Grade Mode:")
      }
    end

    def parse_enrollment_info_html(html)
      doc = Nokogiri::HTML(html)
      section = doc.at_css('section[aria-labelledby="enrollmentInfo"]')

      return nil unless section

      {
        enrollment: {
          actual: extract_span_value(section, "Enrollment Actual:")&.to_i,
          maximum: extract_span_value(section, "Enrollment Maximum:")&.to_i,
          seats_available: seat_count(extract_span_value(section, "Enrollment Seats Available:"))
        },
        waitlist: {
          capacity: extract_span_value(section, "Waitlist Capacity:")&.to_i,
          actual: extract_span_value(section, "Waitlist Actual:")&.to_i,
          seats_available: seat_count(extract_span_value(section, "Waitlist Seats Available:"))
        }
      }
    end

    # Banner reports a negative count when a section holds more students than its
    # cap, for example -8 of 15. Keep it, as Catalog::Importer does, so both write
    # paths store the same number. The courses table allows a negative count.
    def seat_count(raw)
      raw&.to_i
    end

    def extract_labeled_value(section, label)
      label_span = section.xpath(".//span[@class='status-bold'][contains(text(), '#{label}')]").first
      return nil unless label_span

      next_node = label_span.next_sibling
      value = ""

      while next_node && next_node.name != "br" && next_node.name != "span"
        value += next_node.text if next_node.text?
        next_node = next_node.next_sibling
      end

      value.strip.empty? ? nil : value.strip
    end

    def extract_span_value(section, label)
      label_span = section.xpath(".//span[@class='status-bold'][contains(text(), '#{label}')]").first
      return nil unless label_span

      value_span = label_span.xpath("following-sibling::span[@dir='ltr'][1]").first
      return nil unless value_span

      value_span.text.strip
    end

    def handle_error(response)
      raise RequestError.new(
        "LeopardWeb request failed with status #{response.status}: #{response.body}",
        status: response.status
      )
    end

    def get_active_terms
      response = terms_connection.get("courseSearch/getTerms", {
                                        searchTerm: "",
                                        offset: 1,
                                        max: 100
                                      })

      if response.success?
        terms = parse_json_response(response.body)
        {
          success: true,
          terms: terms.map do |t|
            {
              code: t["code"],
              description: t["description"]
            }
          end
        }
      else
        {
          success: false,
          error: "Failed to fetch terms: #{response.status}",
          terms: []
        }
      end
    end

    def get_course_catalog
      raise ArgumentError, "term is required" unless term

      initialize_search_session!

      all_courses = []
      offset = 0
      total_count = nil
      page_size = 500
      first_response_data = nil

      loop do
        response = fetch_catalog_page(offset, page_size)

        if response.success?
          data = parse_json_response(response.body)
          first_response_data ||= data
          courses = data["data"] || []
          total_count ||= data["totalCount"] || 0

          all_courses.concat(courses)

          break if all_courses.length >= total_count || courses.empty?

          offset += page_size
        else
          handle_error(response)
        end
      end

      {
        success: true,
        courses: all_courses,
        total_count: total_count,
        raw_response: first_response_data
      }
    rescue ArgumentError
      raise
    rescue => e
      Rails.error.report(e, handled: true, context: { term: term })
      {
        success: false,
        error: e.message,
        courses: [],
        total_count: 0
      }
    end

    def initialize_search_session!
      response = session_connection.post("term/search") do |req|
        req.params["mode"] = "search"
        req.body = "term=#{term}"
      end

      raise SessionError, "Failed to initialize search session: #{response.status}" unless response.success?

      set_cookie = response.headers["set-cookie"]
      if set_cookie
        match = set_cookie.match(/JSESSIONID=([^;]+)/)
        @session_cookie = match[1] if match
      end

      raise SessionError, "Failed to obtain session cookie" unless @session_cookie

      @session_cookie
    end

    def fetch_catalog_page(offset, page_size)
      unique_session_id = "sess#{SecureRandom.hex(8)}"

      catalog_connection.get("searchResults/searchResults", {
                               txt_term: term,
                               startDatepicker: "",
                               endDatepicker: "",
                               uniqueSessionId: unique_session_id,
                               pageOffset: offset,
                               pageMaxSize: page_size,
                               sortColumn: "subjectDescription",
                               sortDirection: "asc"
                             })
    end

    def terms_connection
      @terms_connection ||= Faraday.new(url: "https://selfservice.wit.edu/StudentRegistrationSsb/ssb/") do |faraday|
        faraday.options.open_timeout = OPEN_TIMEOUT
        faraday.options.timeout = READ_TIMEOUT
        faraday.request :url_encoded
        # Pacing, retries, and the cooldown for every Banner request.
        faraday.use Catalog::BannerThrottle
        faraday.response :json, content_type: /\bjson$/
        faraday.adapter Faraday.default_adapter
      end
    end

    def session_connection
      @session_connection ||= Faraday.new(url: "https://selfservice.wit.edu/StudentRegistrationSsb/ssb/") do |faraday|
        faraday.options.open_timeout = OPEN_TIMEOUT
        faraday.options.timeout = READ_TIMEOUT
        faraday.request :url_encoded
        # Pacing, retries, and the cooldown for every Banner request.
        faraday.use Catalog::BannerThrottle
        faraday.response :json, content_type: /\bjson$/
        faraday.adapter Faraday.default_adapter
      end
    end

    def catalog_connection
      raise SessionError, "Session not initialized - call initialize_search_session! first" unless @session_cookie

      return @catalog_connection if @catalog_connection_cookie == @session_cookie

      @catalog_connection_cookie = @session_cookie
      @catalog_connection = Faraday.new(url: "https://selfservice.wit.edu/StudentRegistrationSsb/ssb/") do |faraday|
        faraday.headers["Accept"] = "application/json, text/javascript, */*; q=0.01"
        faraday.headers["Accept-Language"] = "en-US,en;q=0.9"
        faraday.headers["X-Requested-With"] = "XMLHttpRequest"
        faraday.headers["Referer"] = "https://selfservice.wit.edu/StudentRegistrationSsb/ssb/courseSearch/courseSearch"
        faraday.headers["Cookie"] = "JSESSIONID=#{@session_cookie}"

        faraday.options.open_timeout = OPEN_TIMEOUT
        faraday.options.timeout = READ_TIMEOUT
        faraday.request :url_encoded
        # Pacing, retries, and the cooldown for every Banner request.
        faraday.use Catalog::BannerThrottle
        faraday.response :json, content_type: /\bjson$/
        faraday.adapter Faraday.default_adapter
      end
    end
  end
end

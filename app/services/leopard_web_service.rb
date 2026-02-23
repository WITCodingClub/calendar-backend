# frozen_string_literal: true

# app/services/leopard_web_service.rb
class LeopardWebService < ApplicationService
  require "faraday"
  require "nokogiri"

  BASE_URL = "https://selfservice.wit.edu/StudentRegistrationSsb/ssb/searchResults/"

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
    when :get_available_terms
      get_available_terms
    else
      raise ArgumentError, "Unknown action: #{action}"
    end
  end

  def call!
    call
  end

  # Class method convenience wrappers
  def self.get_class_details(term:, course_reference_number:)
    new(
      action: :get_class_details,
      term: term,
      course_reference_number: course_reference_number
    ).call
  end

  def self.get_enrollment_info
    new(action: :get_enrollment_info).call
  end

  def self.get_faculty_meeting_times(term:, course_reference_number:)
    new(
      action: :get_faculty_meeting_times,
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

  def self.get_available_terms
    new(action: :get_available_terms).call
  end

  private

  def get_class_details
    raise ArgumentError, "term is required" unless term
    raise ArgumentError, "course_reference_number is required" unless course_reference_number

    response = connection.get("getClassDetails", {
                                term: term,
                                courseReferenceNumber: course_reference_number
                              })

    details = handle_response(response, :class_details)

    return nil unless details

    # Separately, get faculty meeting times.
    meeting_times_data = get_faculty_meeting_times

    # Parse and merge meeting times
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
    end

    # Fetch enrollment/seat counts on the same stateful connection (no params required
    # because getEnrollmentInfo uses the session context set by getClassDetails above).
    begin
      enrollment_data = get_enrollment_info
      if enrollment_data
        details[:seats_available] = enrollment_data.dig(:enrollment, :seats_available)
        details[:seats_capacity]  = enrollment_data.dig(:enrollment, :maximum)
      end
    rescue => e
      Rails.logger.warn("LeopardWebService: Failed to fetch enrollment info for CRN #{course_reference_number}: #{e.message}")
    end

    details
  end

  def get_enrollment_info
    response = connection.get("getEnrollmentInfo")
    handle_response(response, :enrollment_info)
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
      faraday.request :url_encoded
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
    # If Faraday has already parsed it, return as-is
    # Otherwise, parse it
    body.is_a?(String) ? JSON.parse(body) : body
  end

  def parse_class_details_html(html)
    doc = Nokogiri::HTML(html)
    section = doc.at_css('section[aria-labelledby="classDetails"]')

    return nil unless section

    {
      associated_term: extract_labeled_value(section, "Associated Term:"),
      crn: section.at_css("#courseReferenceNumber").text.strip,
      campus: extract_labeled_value(section, "Campus:"),
      schedule_type: extract_labeled_value(section, "Schedule Type:"),
      section_number: section.at_css("#sectionNumber").text.strip,
      subject: section.at_css("#subject").text.strip,
      course_number: section.at_css("#courseNumber").text.strip,
      title: section.at_css("#courseTitle").text.strip,
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
        seats_available: extract_span_value(section, "Enrollment Seats Available:")&.to_i
      },
      waitlist: {
        capacity: extract_span_value(section, "Waitlist Capacity:")&.to_i,
        actual: extract_span_value(section, "Waitlist Actual:")&.to_i,
        seats_available: extract_span_value(section, "Waitlist Seats Available:")&.to_i
      }
    }
  end

  def extract_labeled_value(section, label)
    # Find the span with the label text
    label_span = section.xpath(".//span[@class='status-bold'][contains(text(), '#{label}')]").first
    return nil unless label_span

    # Get the text that comes after the label span and before the next <br> or <span>
    next_node = label_span.next_sibling
    value = ""

    while next_node && next_node.name != "br" && next_node.name != "span"
      value += next_node.text if next_node.text?
      next_node = next_node.next_sibling
    end

    value.strip.empty? ? nil : value.strip
  end

  def extract_span_value(section, label)
    # Find the bold label span
    label_span = section.xpath(".//span[@class='status-bold'][contains(text(), '#{label}')]").first
    return nil unless label_span

    # Find the next span with dir="ltr" which contains the value
    value_span = label_span.xpath("following-sibling::span[@dir='ltr'][1]").first
    return nil unless value_span

    value_span.text.strip
  end

  def handle_error(response)
    raise "Request failed with status #{response.status}: #{response.body}"
  end

  def get_available_terms
    response = terms_connection.get("classSearch/getTerms", {
                                      searchTerm: "",
                                      offset: 1,
                                      max: 50
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

    # Initialize a search session (no auth required!)
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
        first_response_data ||= data # Save first response for debugging
        courses = data["data"] || []
        total_count ||= data["totalCount"] || 0

        all_courses.concat(courses)

        # Break if we've fetched all courses
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
    {
      success: false,
      error: e.message,
      courses: [],
      total_count: 0
    }
  end

  # Initialize a search session by POSTing term selection
  # This creates a JSESSIONID cookie that allows subsequent searches without user auth
  def initialize_search_session!
    response = session_connection.post("term/search") do |req|
      req.params["mode"] = "search"
      req.body = "term=#{term}"
    end

    unless response.success?
      raise "Failed to initialize search session: #{response.status}"
    end

    # Extract JSESSIONID from response cookies
    set_cookie = response.headers["set-cookie"]
    if set_cookie
      match = set_cookie.match(/JSESSIONID=([^;]+)/)
      @session_cookie = match[1] if match
    end

    raise "Failed to obtain session cookie" unless @session_cookie

    @session_cookie
  end

  def fetch_catalog_page(offset, page_size)
    # Generate a unique session ID for this request (mimics browser behavior)
    unique_session_id = "sess#{Time.now.to_i}#{rand(1000..9999)}"

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

  # Connection for fetching available terms (no session required)
  def terms_connection
    @terms_connection ||= Faraday.new(url: "https://selfservice.wit.edu/StudentRegistrationSsb/ssb/") do |faraday|
      # Statsd removed
      faraday.request :url_encoded
      faraday.response :json, content_type: /\bjson$/
      faraday.adapter Faraday.default_adapter
    end
  end

  # Connection for initializing the search session
  def session_connection
    @session_connection ||= Faraday.new(url: "https://selfservice.wit.edu/StudentRegistrationSsb/ssb/") do |faraday|
      # Statsd removed
      faraday.request :url_encoded
      faraday.response :json, content_type: /\bjson$/
      faraday.adapter Faraday.default_adapter
    end
  end

  # Connection for fetching catalog pages using the self-created session
  def catalog_connection
    raise "Session not initialized - call initialize_search_session! first" unless @session_cookie

    @catalog_connection ||= Faraday.new(url: "https://selfservice.wit.edu/StudentRegistrationSsb/ssb/") do |faraday|
      # Statsd removed

      faraday.headers["Accept"] = "application/json, text/javascript, */*; q=0.01"
      faraday.headers["Accept-Language"] = "en-US,en;q=0.9"
      faraday.headers["X-Requested-With"] = "XMLHttpRequest"
      faraday.headers["Referer"] = "https://selfservice.wit.edu/StudentRegistrationSsb/ssb/courseSearch/courseSearch"
      faraday.headers["Cookie"] = "JSESSIONID=#{@session_cookie}"

      faraday.request :url_encoded
      faraday.response :json, content_type: /\bjson$/
      faraday.adapter Faraday.default_adapter
    end
  end

end

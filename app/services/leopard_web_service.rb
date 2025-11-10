# frozen_string_literal: true

# app/services/leopard_web_service.rb
class LeopardWebService < ApplicationService
  require "faraday"
  require "nokogiri"

  BASE_URL = "https://selfservice.wit.edu/StudentRegistrationSsb/ssb/searchResults/"

  attr_reader :term, :course_reference_number, :action, :jsessionid, :idmsessid

  def initialize(action:, term: nil, course_reference_number: nil, jsessionid: nil, idmsessid: nil)
    @action = action
    @term = term
    @course_reference_number = course_reference_number
    @jsessionid = jsessionid
    @idmsessid = idmsessid
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

  def self.get_course_catalog(term:, jsessionid:, idmsessid:)
    new(
      action: :get_course_catalog,
      term: term,
      jsessionid: jsessionid,
      idmsessid: idmsessid
    ).call
  end

  private

  def get_class_details
    raise ArgumentError, "term is required" unless term
    raise ArgumentError, "course_reference_number is required" unless course_reference_number

    # Cache class details for 1 hour during registration period, 24 hours otherwise
    # Course details change infrequently once classes are scheduled
    cache_key = "leopard:class_details:#{term}:#{course_reference_number}"
    cache_duration = registration_period? ? 1.hour : 24.hours

    cache_hit = Rails.cache.exist?(cache_key)
    result = Rails.cache.fetch(cache_key, expires_in: cache_duration) do
      # Track cache miss
      StatsD.increment("leopard_web.cache.miss", tags: ["action:get_class_details"])

      response = connection.get("getClassDetails", {
                                  term: term,
                                  courseReferenceNumber: course_reference_number
                                })

      handle_response(response, :class_details)
    end

    # Track cache hit if it existed before fetch
    StatsD.increment("leopard_web.cache.hit", tags: ["action:get_class_details"]) if cache_hit

    result
  end

  def get_enrollment_info
    # Cache enrollment info for 5 minutes since it can change frequently
    cache_key = "leopard:enrollment:#{term}:#{course_reference_number}"

    cache_hit = Rails.cache.exist?(cache_key)
    result = Rails.cache.fetch(cache_key, expires_in: 5.minutes) do
      # Track cache miss
      StatsD.increment("leopard_web.cache.miss", tags: ["action:get_enrollment_info"])

      response = connection.get("getEnrollmentInfo")
      handle_response(response, :enrollment_info)
    end

    # Track cache hit if it existed before fetch
    StatsD.increment("leopard_web.cache.hit", tags: ["action:get_enrollment_info"]) if cache_hit

    result
  end

  def get_faculty_meeting_times
    raise ArgumentError, "term is required" unless term
    raise ArgumentError, "course_reference_number is required" unless course_reference_number

    # Cache meeting times for 1 hour during registration, 24 hours otherwise
    cache_key = "leopard:meeting_times:#{term}:#{course_reference_number}"
    cache_duration = registration_period? ? 1.hour : 24.hours

    cache_hit = Rails.cache.exist?(cache_key)
    result = Rails.cache.fetch(cache_key, expires_in: cache_duration) do
      # Track cache miss
      StatsD.increment("leopard_web.cache.miss", tags: ["action:get_faculty_meeting_times"])

      response = connection.get("getFacultyMeetingTimes", {
                                  term: term,
                                  courseReferenceNumber: course_reference_number
                                })

      handle_response(response, :json)
    end

    # Track cache hit if it existed before fetch
    StatsD.increment("leopard_web.cache.hit", tags: ["action:get_faculty_meeting_times"]) if cache_hit

    result
  end

  def connection
    @connection ||= Faraday.new(url: BASE_URL) do |faraday|
      faraday.use FaradayStatsd
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

  def get_course_catalog
    raise ArgumentError, "term is required" unless term
    raise ArgumentError, "jsessionid is required" unless jsessionid

    # Cache entire course catalog for 7 days since it's relatively static per term
    # This is a large payload but saves multiple paginated API requests
    cache_key = "leopard:catalog:#{term}"

    cache_hit = Rails.cache.exist?(cache_key)
    result = Rails.cache.fetch(cache_key, expires_in: 7.days) do
      # Track cache miss
      StatsD.increment("leopard_web.cache.miss", tags: ["action:get_course_catalog"])
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
    rescue => e
      {
        success: false,
        error: e.message,
        courses: [],
        total_count: 0
      }
    end

    # Track cache hit if it existed before fetch
    StatsD.increment("leopard_web.cache.hit", tags: ["action:get_course_catalog"]) if cache_hit

    result
  end

  def fetch_catalog_page(offset, page_size)
    # Generate a unique session ID for this request (mimics browser behavior)
    unique_session_id = "sess#{Time.now.to_i}#{rand(1000..9999)}"

    authenticated_connection.get("searchResults/searchResults", {
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

  def authenticated_connection
    @authenticated_connection ||= Faraday.new(url: "https://selfservice.wit.edu/StudentRegistrationSsb/ssb/") do |faraday|
      faraday.use FaradayStatsd

      faraday.headers["Accept"] = "application/json, text/javascript, */*; q=0.01"
      faraday.headers["Accept-Language"] = "en-US,en;q=0.9"
      faraday.headers["X-Requested-With"] = "XMLHttpRequest"
      faraday.headers["Referer"] = "https://selfservice.wit.edu/StudentRegistrationSsb/ssb/courseSearch/courseSearch"
      faraday.headers["DNT"] = "1"
      faraday.headers["Sec-Fetch-Dest"] = "empty"
      faraday.headers["Sec-Fetch-Mode"] = "cors"
      faraday.headers["Sec-Fetch-Site"] = "same-origin"

      # Build cookie header with optional IDMSESSID
      cookies = ["JSESSIONID=#{jsessionid}"]
      cookies << "IDMSESSID=#{idmsessid}" if idmsessid.present?
      faraday.headers["Cookie"] = cookies.join("; ")

      faraday.request :url_encoded
      faraday.response :json, content_type: /\bjson$/
      faraday.adapter Faraday.default_adapter
    end
  end

  # Check if we're in a registration period (August-September, January-February)
  # During these months, course data changes more frequently
  def registration_period?
    current_month = Time.current.month
    # August-September (Fall registration) or January-February (Spring registration)
    [1, 2, 8, 9].include?(current_month)
  end

end

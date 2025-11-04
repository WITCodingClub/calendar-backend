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

  private

  def get_class_details
    raise ArgumentError, "term is required" unless term
    raise ArgumentError, "course_reference_number is required" unless course_reference_number

    response = connection.get("getClassDetails", {
                                term: term,
                                courseReferenceNumber: course_reference_number
                              })

    handle_response(response, :class_details)
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

end

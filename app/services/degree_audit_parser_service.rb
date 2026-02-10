# frozen_string_literal: true

# app/services/degree_audit_parser_service.rb
# Parses LeopardWeb degree audit HTML into structured data
class DegreeAuditParserService < ApplicationService
  require "nokogiri"

  class StructureError < StandardError; end
  class ParseError < StandardError; end

  # Expected HTML structure elements for validation
  REQUIRED_ELEMENTS = [
    'section[aria-labelledby="degreeEvaluation"]',
    ".requirement-area",
    ".course-completion"
  ].freeze

  attr_reader :html

  def initialize(html:)
    @html = html
    super()
  end

  def call
    parse
  end

  def call!
    parse
  end

  # Parse the degree audit HTML
  def parse
    doc = Nokogiri::HTML(html)

    # Validate HTML structure before parsing
    validate_html_structure!(doc)

    # Parse the audit data
    {
      program_info: parse_program_info(doc),
      requirements: parse_requirements(doc),
      completed_courses: parse_completed_courses(doc),
      in_progress_courses: parse_in_progress_courses(doc),
      summary: parse_summary(doc)
    }
  rescue Nokogiri::SyntaxError => e
    raise ParseError, "Invalid HTML structure: #{e.message}"
  end

  private

  # Validate that the HTML contains expected structure elements
  def validate_html_structure!(doc)
    missing_elements = REQUIRED_ELEMENTS.reject { |selector| doc.at_css(selector) }

    return if missing_elements.empty?

    error_message = "LeopardWeb HTML structure changed. Missing: #{missing_elements.join(', ')}"
    Rails.logger.error(error_message)

    # Send alert to error tracking (Sentry if available)
    if defined?(Sentry)
      Sentry.capture_message(error_message, level: :error, tags: {
                               component: "degree_audit_parser",
                               change_type: "html_structure"
                             })
    end

    raise StructureError, error_message
  end

  # Parse program information
  def parse_program_info(doc)
    program_section = doc.at_css('section[aria-labelledby="degreeEvaluation"]')
    return {} unless program_section

    {
      program_code: extract_text(program_section, ".program-code"),
      program_name: extract_text(program_section, ".program-name"),
      catalog_year: extract_text(program_section, ".catalog-year"),
      evaluation_date: extract_text(program_section, ".evaluation-date")
    }
  end

  # Parse degree requirements
  def parse_requirements(doc)
    requirement_areas = doc.css(".requirement-area")
    requirement_areas.map do |area|
      {
        area_name: extract_text(area, ".area-name"),
        credits_required: extract_text(area, ".credits-required")&.to_f,
        credits_completed: extract_text(area, ".credits-completed")&.to_f,
        status: extract_text(area, ".status"),
        courses: parse_area_courses(area)
      }
    end
  end

  # Parse courses within a requirement area
  def parse_area_courses(area)
    course_rows = area.css(".course-row")
    course_rows.map do |row|
      {
        subject: extract_text(row, ".subject"),
        course_number: extract_text(row, ".course-number"),
        title: extract_text(row, ".course-title"),
        credits: extract_text(row, ".credits")&.to_f,
        grade: extract_text(row, ".grade"),
        term: extract_text(row, ".term")
      }
    end
  end

  # Parse completed courses
  def parse_completed_courses(doc)
    completion_section = doc.at_css(".course-completion")
    return [] unless completion_section

    completed_rows = completion_section.css(".completed-course")
    completed_rows.map do |row|
      {
        subject: extract_text(row, ".subject"),
        course_number: extract_text(row, ".course-number"),
        title: extract_text(row, ".title"),
        credits: extract_text(row, ".credits")&.to_f,
        grade: extract_text(row, ".grade"),
        term: extract_text(row, ".term"),
        source: extract_text(row, ".source") # Transfer, WIT, etc.
      }
    end
  end

  # Parse in-progress courses
  def parse_in_progress_courses(doc)
    in_progress_section = doc.at_css(".in-progress-courses")
    return [] unless in_progress_section

    in_progress_rows = in_progress_section.css(".in-progress-course")
    in_progress_rows.map do |row|
      {
        subject: extract_text(row, ".subject"),
        course_number: extract_text(row, ".course-number"),
        title: extract_text(row, ".title"),
        credits: extract_text(row, ".credits")&.to_f,
        term: extract_text(row, ".term")
      }
    end
  end

  # Parse summary information
  def parse_summary(doc)
    summary_section = doc.at_css(".degree-summary")
    return {} unless summary_section

    {
      total_credits_required: extract_text(summary_section, ".total-required")&.to_f,
      total_credits_completed: extract_text(summary_section, ".total-completed")&.to_f,
      overall_gpa: extract_text(summary_section, ".overall-gpa")&.to_f,
      requirements_met: extract_text(summary_section, ".requirements-met") == "Yes"
    }
  end

  # Extract text from element matching selector
  def extract_text(parent, selector)
    element = parent.at_css(selector)
    element&.text&.strip.presence
  end

end

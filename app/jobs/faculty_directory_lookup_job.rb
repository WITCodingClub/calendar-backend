# frozen_string_literal: true

# Job to look up a single faculty member from the WIT Faculty Directory.
# This is triggered automatically when a new faculty is created from LeopardWeb
# to enrich their profile with directory data.
#
# @example Look up a faculty member by ID
#   FacultyDirectoryLookupJob.perform_later(faculty.id)
#
class FacultyDirectoryLookupJob < ApplicationJob
  queue_as :low

  def perform(faculty_id)
    faculty = Faculty.find_by(id: faculty_id)
    return unless faculty

    # Skip if already synced recently (within 24 hours)
    if faculty.directory_last_synced_at.present? && faculty.directory_last_synced_at > 24.hours.ago
      Rails.logger.info({
        message: "FacultyDirectoryLookupJob skipped - recently synced",
        faculty_id: faculty.id,
        faculty_name: faculty.full_name,
        last_synced_at: faculty.directory_last_synced_at.iso8601
      }.to_json)
      return
    end

    Rails.logger.info({
      message: "FacultyDirectoryLookupJob starting",
      faculty_id: faculty.id,
      faculty_name: faculty.full_name,
      email: faculty.email,
      job_id: job_id
    }.to_json)

    # Search by last name
    result = FacultyDirectoryService.new(
      search: faculty.last_name,
      fetch_all: false
    ).call

    unless result[:success]
      Rails.logger.warn({
        message: "FacultyDirectoryLookupJob search failed",
        faculty_id: faculty.id,
        error: result[:error],
        job_id: job_id
      }.to_json)
      return
    end

    # Find matching faculty by email
    matching_faculty = result[:faculty].find do |f|
      f[:email]&.downcase == faculty.email.downcase
    end

    if matching_faculty
      update_faculty_from_directory(faculty, matching_faculty)
    else
      Rails.logger.info({
        message: "FacultyDirectoryLookupJob no match found",
        faculty_id: faculty.id,
        faculty_name: faculty.full_name,
        email: faculty.email,
        search_results_count: result[:faculty].length,
        job_id: job_id
      }.to_json)

      # Mark as synced even if not found (to avoid repeated lookups)
      faculty.update!(directory_last_synced_at: Time.current)
    end
  end

  private

  def update_faculty_from_directory(faculty, directory_data)
    name_parts = parse_name(directory_data[:display_name])

    # Merge directory data with existing data instead of overwriting
    attrs = merge_faculty_attributes(faculty, directory_data, name_parts)
    faculty.assign_attributes(attrs)

    if faculty.changed?
      faculty.save!
      Rails.logger.info({
        message: "FacultyDirectoryLookupJob updated faculty",
        faculty_id: faculty.id,
        faculty_name: faculty.full_name,
        changes: faculty.previous_changes.keys,
        job_id: job_id
      }.to_json)

      # Download photo if URL changed
      if faculty.saved_change_to_photo_url? && faculty.photo_url.present?
        faculty.update_photo_from_url!(faculty.photo_url)
      end
    else
      Rails.logger.info({
        message: "FacultyDirectoryLookupJob no changes needed",
        faculty_id: faculty.id,
        faculty_name: faculty.full_name,
        job_id: job_id
      }.to_json)
    end
  end

  def merge_faculty_attributes(faculty, directory_data, name_parts)
    attrs = {
      directory_raw_data: build_raw_data(directory_data),
      directory_last_synced_at: Time.current
    }

    # Name fields - prefer directory data for full names, but don't overwrite with shorter names
    if name_parts[:first_name].present? && (faculty.first_name.blank? || (name_parts[:first_name].length > faculty.first_name.length))
      attrs[:first_name] = name_parts[:first_name]
    end

    if name_parts[:last_name].present? && (faculty.last_name.blank? || (name_parts[:last_name].length > faculty.last_name.length))
      attrs[:last_name] = name_parts[:last_name]
    end

    # Middle name - merge if directory has it
    if name_parts[:middle_name].present? && faculty.middle_name.blank?
      attrs[:middle_name] = name_parts[:middle_name]
    end

    # Display name - always update if directory has a better/longer name
    if directory_data[:display_name].present? && (faculty.display_name.blank? || directory_data[:display_name].length > faculty.display_name.to_s.length)
      attrs[:display_name] = directory_data[:display_name]
    end

    # Title - merge if empty or directory has new info
    if directory_data[:title].present? && (faculty.title.blank? || faculty.title != directory_data[:title])
      attrs[:title] = directory_data[:title]
    end

    # Phone - merge if empty or different
    if directory_data[:phone].present? && (faculty.phone.blank? || faculty.phone != directory_data[:phone])
      attrs[:phone] = directory_data[:phone]
    end

    # Office location - merge if empty
    if directory_data[:office_location].present? && faculty.office_location.blank?
      attrs[:office_location] = directory_data[:office_location]
    end

    # Department - merge if empty
    if directory_data[:department].present? && faculty.department.blank?
      attrs[:department] = directory_data[:department]
    end

    # School - merge if empty
    if directory_data[:school].present? && faculty.school.blank?
      attrs[:school] = directory_data[:school]
    end

    # Photo URL - update if changed or new
    if directory_data[:photo_url].present? && (faculty.photo_url.blank? || faculty.photo_url != directory_data[:photo_url])
      attrs[:photo_url] = directory_data[:photo_url]
    end

    # Employee type - set if not already set
    if faculty.employee_type.blank?
      attrs[:employee_type] = determine_employee_type(directory_data)
    end

    attrs
  end

  def parse_name(display_name)
    return {} if display_name.blank?

    parts = display_name.strip.split(/\s+/)

    case parts.length
    when 0
      {}
    when 1
      { first_name: parts[0], last_name: parts[0] }
    when 2
      { first_name: parts[0], last_name: parts[1] }
    else
      {
        first_name: parts[0],
        middle_name: parts[1..-2].join(" "),
        last_name: parts[-1]
      }
    end
  end

  def determine_employee_type(faculty_data)
    title = faculty_data[:title]&.downcase || ""

    faculty_keywords = %w[professor instructor lecturer dean chair faculty adjunct]
    return "faculty" if faculty_keywords.any? { |keyword| title.include?(keyword) }

    "staff"
  end

  def build_raw_data(faculty_data)
    {
      fetched_at: Time.current.iso8601,
      raw_html: faculty_data[:raw_html],
      profile_url: faculty_data[:profile_url],
      source_url: FacultyDirectoryService::BASE_URL
    }
  end

end

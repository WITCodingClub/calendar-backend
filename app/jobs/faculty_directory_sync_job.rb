# frozen_string_literal: true

# Job to sync all faculty/staff from the WIT Faculty Directory.
# This fetches all pages from the directory and creates/updates Faculty records.
#
# @example Trigger a full sync
#   FacultyDirectorySyncJob.perform_later
#
class FacultyDirectorySyncJob < ApplicationJob
  queue_as :low

  def perform
    Rails.logger.info({
      message: "FacultyDirectorySyncJob starting",
      job_id: job_id
    }.to_json)

    # Fetch all faculty from directory
    result = FacultyDirectoryService.call

    unless result[:success]
      Rails.logger.error({
        message: "FacultyDirectorySyncJob failed to fetch directory",
        error: result[:error],
        job_id: job_id
      }.to_json)
      raise "Failed to fetch faculty directory: #{result[:error]}"
    end

    stats = { created: 0, updated: 0, skipped: 0, errors: [] }

    result[:faculty].each do |faculty_data|
      process_faculty(faculty_data, stats)
    end

    Rails.logger.info({
      message: "FacultyDirectorySyncJob completed",
      job_id: job_id,
      total_fetched: result[:total_count],
      created: stats[:created],
      updated: stats[:updated],
      skipped: stats[:skipped],
      errors_count: stats[:errors].length
    }.to_json)

    stats
  end

  private

  def process_faculty(faculty_data, stats)
    email = faculty_data[:email]&.downcase&.strip
    if email.blank?
      stats[:skipped] += 1
      return
    end

    # Parse name components
    name_parts = parse_name(faculty_data[:display_name])

    faculty = Faculty.find_or_initialize_by(email: email)
    was_new = faculty.new_record?

    # For new records, require first/last name
    if was_new && (name_parts[:first_name].blank? || name_parts[:last_name].blank?)
      stats[:skipped] += 1
      return
    end

    # Merge directory data with existing data instead of overwriting
    # Only update fields if directory has better data
    attrs = merge_faculty_attributes(faculty, faculty_data, name_parts)
    faculty.assign_attributes(attrs)

    if faculty.changed?
      faculty.save!
      was_new ? stats[:created] += 1 : stats[:updated] += 1

      # Download photo if URL changed
      if faculty.saved_change_to_photo_url? && faculty.photo_url.present?
        faculty.update_photo_from_url!(faculty.photo_url)
      end
    else
      stats[:skipped] += 1
    end
  rescue => e
    Rails.logger.error({
      message: "FacultyDirectorySyncJob error processing faculty",
      email: email,
      error: e.message,
      job_id: job_id
    }.to_json)
    stats[:errors] << { email: email, error: e.message }
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

    # Office location - merge if empty or different
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
      # Handle "First Middle Last" format
      {
        first_name: parts[0],
        middle_name: parts[1..-2].join(" "),
        last_name: parts[-1]
      }
    end
  end

  def determine_employee_type(faculty_data)
    title = faculty_data[:title]&.downcase || ""

    # Check for faculty indicators
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

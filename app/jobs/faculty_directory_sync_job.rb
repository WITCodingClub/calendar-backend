# frozen_string_literal: true

class FacultyDirectorySyncJob < ApplicationJob
  queue_as :low

  def perform
    Rails.logger.info({ message: "FacultyDirectorySyncJob starting", job_id: job_id }.to_json)

    result = FacultyDirectoryService.call

    unless result[:success]
      Rails.logger.error({ message: "FacultyDirectorySyncJob failed to fetch directory",
                           error: result[:error], job_id: job_id }.to_json)
      raise "Failed to fetch faculty directory: #{result[:error]}"
    end

    stats = { created: 0, updated: 0, skipped: 0, errors: [] }

    emails = result[:faculty].filter_map { |f| f[:email]&.downcase&.strip }.uniq
    @faculty_cache = Faculty.where(email: emails).index_by(&:email)

    result[:faculty].each { |faculty_data| process_faculty(faculty_data, stats) }

    Rails.cache.delete_matched("faculty_directory:page:*")
    Rails.cache.write("faculty_directory_last_full_sync_at", Time.current, expires_in: 2.days)

    Rails.logger.info({ message: "FacultyDirectorySyncJob completed", job_id: job_id,
                        total_fetched: result[:total_count], created: stats[:created],
                        updated: stats[:updated], skipped: stats[:skipped],
                        errors_count: stats[:errors].length }.to_json)

    stats
  end

  private

  def process_faculty(faculty_data, stats)
    email = faculty_data[:email]&.downcase&.strip
    if email.blank?
      stats[:skipped] += 1
      return
    end

    name_parts = parse_name(faculty_data[:display_name])
    faculty = @faculty_cache&.fetch(email, nil) || Faculty.new(email: email)
    was_new = faculty.new_record?

    if was_new && (name_parts[:first_name].blank? || name_parts[:last_name].blank?)
      stats[:skipped] += 1
      return
    end

    attrs = merge_faculty_attributes(faculty, faculty_data, name_parts)
    faculty.assign_attributes(attrs)

    if faculty.changed?
      faculty.save!
      was_new ? stats[:created] += 1 : stats[:updated] += 1
      faculty.update_photo_from_url!(faculty.photo_url) if faculty.saved_change_to_photo_url? && faculty.photo_url.present?
    else
      stats[:skipped] += 1
    end
  rescue => e
    Rails.logger.error({ message: "FacultyDirectorySyncJob error processing faculty",
                         email: email, error: e.message, job_id: job_id }.to_json)
    stats[:errors] << { email: email, error: e.message }
  end

  def merge_faculty_attributes(faculty, directory_data, name_parts)
    attrs = { directory_raw_data: build_raw_data(directory_data), directory_last_synced_at: Time.current }

    if name_parts[:first_name].present? && (faculty.first_name.blank? || name_parts[:first_name].length > faculty.first_name.length)
      attrs[:first_name] = name_parts[:first_name]
    end
    if name_parts[:last_name].present? && (faculty.last_name.blank? || name_parts[:last_name].length > faculty.last_name.length)
      attrs[:last_name] = name_parts[:last_name]
    end
    attrs[:middle_name]    = name_parts[:middle_name]       if name_parts[:middle_name].present? && faculty.middle_name.blank?
    attrs[:display_name]   = directory_data[:display_name]  if directory_data[:display_name].present? && (faculty.display_name.blank? || directory_data[:display_name].length > faculty.display_name.to_s.length)
    attrs[:title]          = directory_data[:title]         if directory_data[:title].present? && faculty.title != directory_data[:title]
    attrs[:phone]          = directory_data[:phone]         if directory_data[:phone].present? && faculty.phone != directory_data[:phone]
    attrs[:office_location] = directory_data[:office_location] if directory_data[:office_location].present? && faculty.office_location.blank?
    attrs[:department]     = directory_data[:department]    if directory_data[:department].present? && faculty.department.blank?
    attrs[:school]         = directory_data[:school]        if directory_data[:school].present? && faculty.school.blank?
    attrs[:photo_url]      = directory_data[:photo_url]     if directory_data[:photo_url].present? && faculty.photo_url != directory_data[:photo_url]
    attrs[:employee_type]  = determine_employee_type(directory_data) if faculty.employee_type.blank?
    attrs
  end

  def parse_name(display_name)
    return {} if display_name.blank?

    parts = display_name.strip.split(/\s+/)
    case parts.length
    when 0 then {}
    when 1 then { first_name: parts[0], last_name: parts[0] }
    when 2 then { first_name: parts[0], last_name: parts[1] }
    else { first_name: parts[0], middle_name: parts[1..-2].join(" "), last_name: parts[-1] }
    end
  end

  def determine_employee_type(faculty_data)
    title = faculty_data[:title]&.downcase || ""
    %w[professor instructor lecturer dean chair faculty adjunct].any? { |kw| title.include?(kw) } ? "faculty" : "staff"
  end

  def build_raw_data(faculty_data)
    {
      fetched_at:  Time.current.iso8601,
      raw_html:    faculty_data[:raw_html],
      profile_url: faculty_data[:profile_url],
      source_url:  FacultyDirectoryService::BASE_URL
    }
  end
end

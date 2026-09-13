# frozen_string_literal: true

# Makes a section's instructor list match what Banner reports, and records which
# instructor Banner marks as primary.
#
# The two importers used to only add. Nothing ever detached an instructor, so a
# section that changed hands kept both people forever and the calendar rendered
# whichever join row was oldest. Attaching and detaching in one place also keeps
# CourseProcessorService and CatalogImportService from drifting apart.
class FacultyIngestService < ApplicationService
  attr_reader :course, :raw_faculty

  def initialize(course:, raw_faculty:)
    @course = course
    @raw_faculty = Array(raw_faculty)
    super()
  end

  # Returns true when the section's instructor list or primary instructor
  # changed, so callers can report a real update.
  #
  # A blank payload means Banner told us nothing, not that the section lost its
  # instructor. Detaching on it would strip every section the moment a request
  # failed, the same reasoning CourseDataSyncJob uses before pruning meeting
  # times.
  def call
    entries = normalized_entries
    return false if entries.empty?

    before = fingerprint

    attached_ids = entries.map { |entry| attach(entry) }
    course.course_faculties.where.not(faculty_id: attached_ids).destroy_all

    course.course_faculties.reset
    course.faculties.reset

    return false if before == fingerprint

    # A new instructor changes the event description, and nothing else notices:
    # CourseChangeTrackable only watches columns on courses.
    course.mark_enrolled_users_for_sync
    true
  end

  private

  def fingerprint
    CourseFaculty.where(course_id: course.id)
                 .in_banner_order
                 .pluck(:faculty_id, :primary_indicator)
  end

  # Banner sends "Sanderson, Elijah" from the catalog search and "Elijah
  # Sanderson" from getFacultyMeetingTimes, and the extension posts a bare name
  # with no email at all. Reduce all of them to one shape before writing.
  def normalized_entries
    raw_faculty.filter_map { |member|
      next if member.blank?

      email = fetch(member, "emailAddress", :emailAddress).to_s.strip.downcase
      display_name = fetch(member, "displayName", :displayName).to_s.strip
      next if email.blank? || display_name.blank?

      first_name, last_name = parse_name(display_name)
      next if first_name.blank? || last_name.blank?

      {
        email: email,
        first_name: first_name,
        last_name: last_name,
        primary: ActiveModel::Type::Boolean.new.cast(
          fetch(member, "primaryIndicator", :primaryIndicator)
        ) || false
      }
    }.uniq { |entry| entry[:email] }
  end

  def attach(entry)
    faculty = find_or_create_faculty(entry)

    join = course.course_faculties.find_or_initialize_by(faculty_id: faculty.id)
    join.primary_indicator = entry[:primary]
    join.save! if join.new_record? || join.changed?

    faculty.id
  end

  # Banner sends lowercase addresses, but rows written before this service ran
  # can carry any casing. Match on the lowered address so a re-import updates
  # the existing instructor instead of creating a second one.
  def find_or_create_faculty(entry)
    existing = Faculty.find_by("LOWER(email) = ?", entry[:email])
    return existing if existing

    Faculty.create!(
      email: entry[:email],
      first_name: entry[:first_name],
      last_name: entry[:last_name]
    )
  rescue ActiveRecord::RecordNotUnique
    Faculty.find_by!("LOWER(email) = ?", entry[:email])
  end

  def fetch(member, string_key, symbol_key)
    member[string_key] || member[symbol_key]
  end

  def parse_name(display_name)
    if display_name.include?(",")
      last_name, rest = display_name.split(",", 2).map(&:strip)
      [ rest.to_s.split(/\s+/).first, last_name ]
    else
      parts = display_name.split(/\s+/)
      parts.length >= 2 ? [ parts.first, parts.last ] : [ display_name, display_name ]
    end
  end
end

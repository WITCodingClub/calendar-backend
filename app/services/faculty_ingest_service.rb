# frozen_string_literal: true

# Makes a section's instructor list match what Banner reports, and records which
# instructor Banner marks as primary.
#
# The two importers used to only add. Nothing ever detached an instructor, so a
# section that changed hands kept both people forever and the calendar rendered
# whichever join row was oldest. Attaching and detaching in one place also keeps
# Courses::Processor and Catalog::Importer from drifting apart.
class FacultyIngestService < ApplicationService
  attr_reader :course, :raw_faculty

  # Options, for a caller that ingests many courses:
  # - faculty: a hash of lowercased email => Faculty, shared with the ingests of
  #   other courses. See preload.
  # - existing_course_faculties: the course's join rows, loaded by the caller.
  #   Without it, the ingest loads them itself.
  def initialize(course:, raw_faculty:, **options)
    @course = course
    @raw_faculty = Array(raw_faculty)
    @faculty_cache = options[:faculty] || {}
    @existing_course_faculties = options[:existing_course_faculties]
    super()
  end

  # Loads the instructors that the raw faculty lists name into cache, keyed by
  # lowercased email, in one query. Sends no query for an email that is already
  # in cache.
  def self.preload(raw_faculty_lists, cache = {})
    emails = raw_faculty_lists.flat_map { |raw| new(course: nil, raw_faculty: raw).entry_emails }.uniq - cache.keys
    return cache if emails.empty?

    Faculty.where("LOWER(email) IN (?)", emails).order(:id).each do |faculty|
      cache[faculty.email.downcase] ||= faculty
    end
    # Keep a nil for each email with no row, so a later call creates the
    # instructor instead of looking for it again.
    emails.each { |email| cache[email] = nil unless cache.key?(email) }
    cache
  end

  # Returns true when the section's instructor list or primary instructor
  # changed, so callers can report a real update.
  #
  # A blank payload means Banner told us nothing, not that the section lost its
  # instructor. Detaching on it would strip every section the moment a request
  # failed, the same reasoning Catalog::CourseDataSyncJob uses before pruning meeting
  # times.
  def call
    entries = normalized_entries
    return false if entries.empty?

    joins = @existing_course_faculties || CourseFaculty.where(course_id: course.id).to_a
    before = fingerprint(joins)

    self.class.preload([ raw_faculty ], @faculty_cache)
    kept = entries.map { |entry| attach(joins, entry) }
    (joins - kept).each(&:destroy)

    course.course_faculties.reset
    course.faculties.reset

    return false if before == fingerprint(kept)

    # A new instructor changes the event description, and nothing else notices:
    # CourseChangeTrackable only watches columns on courses.
    course.mark_enrolled_users_for_sync
    true
  end

  def entry_emails
    normalized_entries.pluck(:email)
  end

  private

  # The order of CourseFaculty.in_banner_order, read from the loaded rows.
  def fingerprint(joins)
    joins.sort_by { |join| [ join.primary_indicator ? 0 : 1, join.id ] }
         .map { |join| [ join.faculty_id, join.primary_indicator ] }
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

  def attach(joins, entry)
    faculty = find_or_create_faculty(entry)

    join = joins.find { |existing| existing.faculty_id == faculty.id } ||
           CourseFaculty.new(course: course, faculty: faculty)
    join.primary_indicator = entry[:primary]
    join.save! if join.new_record? || join.changed?

    join
  end

  # Banner sends lowercase addresses, but rows written before this service ran
  # can carry any casing. preload matches on the lowered address so a re-import
  # updates the existing instructor instead of creating a second one.
  def find_or_create_faculty(entry)
    @faculty_cache[entry[:email]] ||= begin
      Faculty.create!(
        email: entry[:email],
        first_name: entry[:first_name],
        last_name: entry[:last_name]
      )
    rescue ActiveRecord::RecordNotUnique
      Faculty.find_by!("LOWER(email) = ?", entry[:email])
    end
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

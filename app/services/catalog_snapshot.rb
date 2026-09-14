# frozen_string_literal: true

require "zlib"

# Copies the public course catalog from one database to another. Seeds use it to
# give a development database real terms, courses, rooms, and finals.
#
# Only the columns in TABLES leave the source database. Faculty keep their names,
# title, department, and school. Their email becomes a placeholder, and contact
# details, raw directory HTML, and RateMyProfessor data stay behind. Email
# addresses in free text, such as event descriptions, become a placeholder. No
# table that holds user data is read.
class CatalogSnapshot
  class CatalogNotEmpty < StandardError; end

  FORMAT_VERSION = 1
  DEFAULT_TERM_COUNT = 3
  SEED_PATH = Rails.root.join("db/seeds/catalog.json.gz")

  # Tables in insert order, each with its model and the columns it exports.
  TABLES = {
    "terms"                                    => [ "Term", %w[id uid year season start_date end_date] ],
    "buildings"                                => [ "Building", %w[id abbreviation name formal_name twenty_five_live_id] ],
    "rooms"                                    => [ "Room", %w[id building_id number formal_name floor capacity twenty_five_live_id] ],
    "faculties"                                => [ "Faculty", %w[id first_name middle_name last_name display_name title department school employee_type] ],
    "courses"                                  => [ "Course", %w[id term_id crn subject course_number section_number title schedule_type credit_hours grade_mode start_date end_date status seats_available seats_capacity is_section_linked link_identifier] ],
    "course_meeting_times"                     => [ "Course::MeetingTime", %w[id course_id day_of_week begin_time end_time hours_week meeting_schedule_type meeting_type start_date end_date] ],
    "course_meeting_time_rooms"                => [ "Course::MeetingTimeRoom", %w[id meeting_time_id room_id] ],
    "courses_faculties"                        => [ "CourseFaculty", %w[id course_id faculty_id primary_indicator] ],
    "final_exams"                              => [ "FinalExam", %w[id term_id course_id crn combined_crns exam_date start_time end_time location notes] ],
    "university_calendar_events"               => [ "UniversityCalendarEvent", %w[id term_id ics_uid summary description category event_type_raw academic_term organization location source_url all_day start_time end_time recurrence last_fetched_at] ],
    "twenty_five_live_organizations"           => [ "TwentyFiveLive::Organization", %w[id twenty_five_live_id name code organization_type_name] ],
    "twenty_five_live_event_categories"        => [ "TwentyFiveLive::EventCategory", %w[id twenty_five_live_id name sort_order defn_state] ],
    "twenty_five_live_event_custom_attributes" => [ "TwentyFiveLive::EventCustomAttribute", %w[id twenty_five_live_id name attribute_type attribute_type_name multi_val sort_order defn_state] ],
    "twenty_five_live_resources"               => [ "TwentyFiveLive::Resource", %w[id twenty_five_live_id name assign_perm schedule_perm stock_level] ]
  }.freeze

  def self.export(term_count: DEFAULT_TERM_COUNT) = new.export(term_count: term_count)

  def self.import(data) = new.import(data)

  def self.write(path, data)
    Zlib::GzipWriter.open(path.to_s) { |gz| gz.write(JSON.generate(data)) }
  end

  def self.read(path)
    JSON.parse(Zlib::GzipReader.open(path.to_s, &:read))
  end

  def self.placeholder_email(faculty_id) = "faculty-#{faculty_id}@example.com"

  EMAIL_PATTERN = /[\w.+-]+@[\w-]+(?:\.[\w-]+)+/
  REDACTED_EMAIL = "redacted@example.com"

  # Free text that can name a person's address. ics_uid is not here: it is
  # unique and can look like an address, so scrubbing it would break the import.
  SCRUBBED_COLUMNS = {
    "university_calendar_events" => %w[summary description location organization],
    "final_exams"                => %w[notes location]
  }.freeze

  # Replaces every email address in SCRUBBED_COLUMNS with REDACTED_EMAIL.
  def self.scrub_emails(tables)
    SCRUBBED_COLUMNS.each do |table, columns|
      tables.fetch(table, []).each do |row|
        columns.each { |column| row[column] = row[column].gsub(EMAIL_PATTERN, REDACTED_EMAIL) if row[column].is_a?(String) }
      end
    end
    tables
  end

  # Rows come from pluck, so JSON and enum columns hold Ruby values. insert_all!
  # serializes them through the same attribute types, which keeps text columns
  # that store JSON, such as final_exams.combined_crns, from double encoding.
  def export(term_count:)
    scopes = export_scopes(term_count)
    tables = TABLES.to_h { |table, (_model, columns)| [ table, rows(scopes.fetch(table), columns) ] }
    self.class.scrub_emails(tables)
    tables["faculties"].each { |row| row["email"] = self.class.placeholder_email(row["id"]) }

    { "format_version" => FORMAT_VERSION, "exported_at" => Time.current.iso8601, "tables" => tables }
  end

  # Keeps the source ids, so the target must hold no catalog rows. insert_all!
  # skips callbacks, which keeps Faculty from queueing directory lookups.
  def import(data)
    unless data["format_version"] == FORMAT_VERSION
      raise ArgumentError, "unsupported catalog snapshot format: #{data["format_version"].inspect}"
    end

    occupied = TABLES.filter_map { |table, (model, _columns)| table if model.constantize.exists? }
    raise CatalogNotEmpty, "import needs empty catalog tables; these have rows: #{occupied.join(", ")}" if occupied.any?

    ActiveRecord::Base.transaction do
      TABLES.each do |table, (model, _columns)|
        rows = data.fetch("tables").fetch(table)
        next if rows.empty?

        model.constantize.insert_all!(rows)
        ActiveRecord::Base.connection.reset_pk_sequence!(table)
      end
    end
  end

  private

  def export_scopes(term_count)
    term_ids = Term.where(id: Course.select(:term_id)).order(uid: :desc).limit(term_count).ids
    course_ids = Course.where(term_id: term_ids).select(:id)
    meeting_time_ids = Course::MeetingTime.where(course_id: course_ids).select(:id)
    course_faculties = CourseFaculty.where(course_id: course_ids)

    {
      "terms"                                    => Term.where(id: term_ids),
      "buildings"                                => Building.all,
      "rooms"                                    => Room.all,
      "faculties"                                => Faculty.where(id: course_faculties.select(:faculty_id)),
      "courses"                                  => Course.where(id: course_ids),
      "course_meeting_times"                     => Course::MeetingTime.where(id: meeting_time_ids),
      "course_meeting_time_rooms"                => Course::MeetingTimeRoom.where(meeting_time_id: meeting_time_ids),
      "courses_faculties"                        => course_faculties,
      "final_exams"                              => FinalExam.where(term_id: term_ids),
      "university_calendar_events"               => UniversityCalendarEvent.where(term_id: [ nil, *term_ids ]),
      "twenty_five_live_organizations"           => TwentyFiveLive::Organization.all,
      "twenty_five_live_event_categories"        => TwentyFiveLive::EventCategory.all,
      "twenty_five_live_event_custom_attributes" => TwentyFiveLive::EventCustomAttribute.all,
      "twenty_five_live_resources"               => TwentyFiveLive::Resource.all
    }
  end

  def rows(scope, columns)
    scope.reorder(:id).pluck(*columns).map { |values| columns.zip(values).to_h }
  end
end

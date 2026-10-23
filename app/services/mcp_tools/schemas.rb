# frozen_string_literal: true

module McpTools
  # JSON Schemas for the structured results of the MCP tools (each tool's
  # output_schema). Clients use them to check and read a result, and the MCP
  # spec says a result must conform to the schema its tool declares.
  #
  # The shapes follow the serializers and query objects that build the
  # results. When a serializer changes, change its schema here in the same PR:
  # spec/services/mcp_tools/output_schemas_spec.rb calls every tool and
  # checks the result against its schema.
  #
  # Rules: a key that can hold nil is nullable, `required` lists only the
  # keys that are always present, and objects take more keys, so a new field
  # does not break a client.
  module Schemas
    # An object schema. Every key is required, except the optional ones: keys
    # that a result can leave out. Pass the properties as a Hash, or as
    # keywords when no property is named optional.
    def self.object(properties = {}, optional: [], **more)
      properties = properties.merge(more)
      { type: "object", properties: properties, required: (properties.keys - optional).map(&:to_s) }
    end

    # The schema, or null.
    def self.nullable(schema)
      schema.merge(type: [ *Array(schema[:type]), "null" ])
    end

    def self.array(items) = { type: "array", items: items }

    STRING    = { type: "string" }.freeze
    INTEGER   = { type: "integer" }.freeze
    NUMBER    = { type: "number" }.freeze
    BOOLEAN   = { type: "boolean" }.freeze
    DATE      = { type: "string", format: "date" }.freeze
    DATE_TIME = { type: "string", format: "date-time" }.freeze
    # A 24-hour time, HH:MM.
    TIME      = { type: "string", pattern: "^([01][0-9]|2[0-3]):[0-5][0-9]$" }.freeze
    # A busy block that runs to midnight ends at "24:00" (BusyBlocks).
    BUSY_TIME = { type: "string", pattern: "^(([01][0-9]|2[0-3]):[0-5][0-9]|24:00)$" }.freeze
    DAY       = { type: "string", enum: Course::MeetingTime.day_of_weeks.keys }.freeze

    STRINGS  = array(STRING).freeze
    INTEGERS = array(INTEGER).freeze

    # Paging of a list tool (BaseTool#page_meta).
    PAGE_META = object(
      page:        INTEGER,
      per_page:    INTEGER,
      total_count: INTEGER,
      total_pages: INTEGER
    ).freeze

    # Catalog::TermSerializer. It leaves out a nil date or section count.
    TERM = object(
      {
        uid:           INTEGER,
        name:          STRING,
        season:        STRING,
        year:          INTEGER,
        start_date:    DATE,
        end_date:      DATE,
        section_count: INTEGER
      },
      optional: %i[start_date end_date section_count]
    ).freeze

    TERM_REF = object(uid: INTEGER, name: STRING).freeze

    SUBJECT = object(subject: STRING, code: STRING, section_count: INTEGER).freeze

    # Catalog::InstructorSerializer.rmp_for. Nil when there are no ratings.
    RMP = nullable(
      object(
        id:                       nullable(STRING),
        avg_rating:               nullable(NUMBER),
        avg_difficulty:           nullable(NUMBER),
        num_ratings:              INTEGER,
        would_take_again_percent: nullable(NUMBER)
      )
    ).freeze

    # Catalog::InstructorSerializer.
    INSTRUCTOR = object(
      pub_id:     STRING,
      name:       STRING,
      first_name: STRING,
      last_name:  STRING,
      title:      nullable(STRING),
      department: nullable(STRING),
      school:     nullable(STRING),
      rmp:        RMP
    ).freeze

    # Catalog::MeetingTimeSerializer.
    MEETING_TIME = object(
      day:              DAY,
      day_of_week:      { type: "integer", minimum: 0, maximum: 6 },
      begin_time:       TIME,
      end_time:         TIME,
      begin_time_12h:   STRING,
      end_time_12h:     STRING,
      duration_minutes: INTEGER,
      meeting_type:     { type: "string", enum: Course::MeetingTime.meeting_schedule_types.keys },
      all_day:          BOOLEAN,
      location:         nullable(
        object(
          display:  nullable(STRING),
          building: object(abbreviation: STRING, name: STRING),
          rooms:    array(object(number: STRING, floor: INTEGER))
        )
      )
    ).freeze

    # A node of a prerequisite tree (CatalogCourse): and/or with operands, a
    # course, or a placement test. A course node from
    # Catalog::CourseSerializer also has code, title, and linked.
    PREREQUISITE = {
      type:       "object",
      properties: {
        type:          { type: "string", enum: %w[and or course test] },
        operands:      array({ type: "object" }),
        subject_code:  STRING,
        course_number: INTEGER,
        code:          STRING,
        title:         nullable(STRING),
        linked:        BOOLEAN,
        min_grade:     nullable(STRING),
        level:         nullable(STRING),
        name:          STRING,
        score:         nullable(STRING)
      },
      required:   %w[type]
    }.freeze

    # Catalog::SectionLinks.
    LINKED = object(
      required:   BOOLEAN,
      identifier: nullable(STRING),
      source:     { type: "string", enum: %w[banner link_identifier] },
      crns:       INTEGERS,
      pub_ids:    STRINGS,
      options:    array(INTEGERS)
    ).freeze

    # Catalog::SectionSerializer. Catalog::CourseSerializer leaves out course.
    SECTION_PROPERTIES = {
      crn:                INTEGER,
      pub_id:             STRING,
      term:               TERM_REF,
      subject:            STRING,
      subject_code:       STRING,
      course_number:      INTEGER,
      section_number:     STRING,
      course_code:        STRING,
      title:              STRING,
      schedule_type:      STRING,
      schedule_type_code: nullable(STRING),
      credit_hours:       nullable(INTEGER),
      grade_mode:         nullable(STRING),
      status:             { type: "string", enum: %w[active cancelled] },
      seats:              object(capacity: nullable(INTEGER), available: nullable(INTEGER)),
      linked:             LINKED,
      start_date:         DATE,
      end_date:           DATE,
      instructors:        array(INSTRUCTOR),
      meeting_times:      array(MEETING_TIME),
      final_exam:         nullable(
        object(date: DATE, start_time: nullable(TIME), end_time: nullable(TIME), location: nullable(STRING))
      ),
      course:             nullable(
        object(
          code:              STRING,
          description:       nullable(STRING),
          prerequisites:     nullable(PREREQUISITE),
          typically_offered: STRINGS
        )
      )
    }.freeze
    SECTION = object(SECTION_PROPERTIES, optional: %i[course]).freeze

    # Catalog::CourseSerializer.summary.
    COURSE_SUMMARY_PROPERTIES = {
      code:              STRING,
      subject_code:      STRING,
      course_number:     INTEGER,
      title:             nullable(STRING),
      credit_hours:      nullable(INTEGER),
      typically_offered: STRINGS
    }.freeze
    COURSE_SUMMARY = object(COURSE_SUMMARY_PROPERTIES).freeze

    # Catalog::CourseSerializer. sections is there only with a term.
    COURSE_PROPERTIES = COURSE_SUMMARY_PROPERTIES.merge(
      description:        nullable(STRING),
      prerequisites:      nullable(PREREQUISITE),
      corequisites:       array(PREREQUISITE),
      restrictions:       array(object(heading: STRING, values: STRINGS)),
      unlocks:            array(COURSE_SUMMARY),
      details_term_uid:   nullable(INTEGER),
      details_fetched_at: nullable(DATE_TIME),
      sections:           array(SECTION)
    ).freeze
    COURSE = object(COURSE_PROPERTIES, optional: %i[sections]).freeze

    # Catalog::ReviewSerializer. get_instructor leaves out instructor.
    REVIEW_PROPERTIES = {
      pub_id:            STRING,
      instructor:        nullable(object(pub_id: STRING, name: STRING)),
      course_name:       nullable(STRING),
      comment:           nullable(STRING),
      clarity_rating:    nullable(INTEGER),
      difficulty_rating: nullable(INTEGER),
      would_take_again:  nullable(BOOLEAN),
      sentiment:         { type: "string", enum: %w[positive neutral negative] },
      tags:              STRINGS,
      thumbs_up:         nullable(INTEGER),
      thumbs_down:       nullable(INTEGER),
      rated_on:          nullable(DATE),
      source:            STRING
    }.freeze
    REVIEW = object(REVIEW_PROPERTIES).freeze

    # Catalog::InstructorDetailSerializer. sections is there only with a term.
    INSTRUCTOR_DETAIL_PROPERTIES = INSTRUCTOR[:properties].merge(
      rating_distribution: nullable(object(%w[1 2 3 4 5].to_h { |score| [ score.to_sym, nullable(INTEGER) ] })),
      rmp_tags:            array(object(name: STRING, count: nullable(INTEGER))),
      recent_reviews:      array(object(REVIEW_PROPERTIES, optional: %i[instructor])),
      review_count:        INTEGER,
      reviews_source:      STRING,
      sections:            array(SECTION)
    ).freeze
    INSTRUCTOR_DETAIL = object(INSTRUCTOR_DETAIL_PROPERTIES, optional: %i[sections]).freeze

    # A weekly meeting of one of the user's courses
    # (Courses::ProcessedEventsBuilder, without calendar_config). Each day
    # key is true on the day it meets.
    MY_MEETING_TIME = object(
      id:         STRING,
      begin_time: TIME,
      end_time:   TIME,
      start_date: DATE_TIME,
      end_date:   DATE_TIME,
      location:   object(
        building: nullable(object(pub_id: STRING, name: STRING, abbreviation: STRING)),
        rooms:    STRINGS
      ),
      **Course::MeetingTime.day_of_weeks.keys.to_h { |day| [ day.to_sym, BOOLEAN ] }
    ).freeze

    # One of the user's courses (Courses::ProcessedEventsBuilder).
    # my_course_history leaves out term, because the course is under its term.
    MY_COURSE_PROPERTIES = {
      crn:           INTEGER,
      title:         STRING,
      course_number: INTEGER,
      schedule_type: STRING,
      prefix:        STRING,
      term:          object(pub_id: STRING, uid: INTEGER, season: STRING, year: INTEGER),
      professor:     nullable(
        object(pub_id: STRING, first_name: STRING, last_name: STRING, email: STRING, rmp_id: nullable(STRING))
      ),
      meeting_times: array(MY_MEETING_TIME)
    }.freeze
    MY_COURSE = object(MY_COURSE_PROPERTIES).freeze
    MY_COURSE_IN_TERM = object(MY_COURSE_PROPERTIES, optional: %i[term]).freeze

    # BusyBlocksSerializer.
    BUSY_TIMES_PROPERTIES = {
      time_zone:  STRING,
      start_date: DATE,
      end_date:   DATE,
      busy:       array(object(date: DATE, weekday: STRING, start: BUSY_TIME, end: BUSY_TIME))
    }.freeze

    # FriendSerializer, as list_friends and friend_busy_times send it.
    FRIEND = object(id: STRING, name: STRING).freeze

    # EnrolledFinalExamSerializer.
    FINAL_EXAM = object(
      id:            STRING,
      course:        STRING,
      crn:           nullable(INTEGER),
      date:          DATE,
      start_time:    nullable(TIME),
      end_time:      nullable(TIME),
      location:      nullable(STRING),
      location_name: nullable(STRING)
    ).freeze

    # UniversityCalendarEventSerializer.
    UNIVERSITY_EVENT = object(
      id:               STRING,
      summary:          STRING,
      description:      nullable(STRING),
      location:         nullable(STRING),
      start_time:       DATE_TIME,
      end_time:         DATE_TIME,
      all_day:          BOOLEAN,
      category:         nullable(STRING),
      organization:     nullable(STRING),
      academic_term:    nullable(STRING),
      term_id:          nullable(STRING),
      excludes_classes: BOOLEAN,
      formatted_date:   STRING,
      created_at:       DATE_TIME,
      updated_at:       DATE_TIME
    ).freeze

    # A stored reminder. The stored form has string times; the setting tools
    # take numbers.
    REMINDER = object(
      time:   { type: %w[string number] },
      type:   STRING,
      method: STRING
    ).freeze

    # EventPreferenceSerializer: the settings of one level. A nil field
    # leaves the level below in charge.
    SETTINGS_PROPERTIES = {
      title_template:       nullable(STRING),
      description_template: nullable(STRING),
      location_template:    nullable(STRING),
      reminder_settings:    nullable(array(REMINDER)),
      color_id:             nullable(STRING),
      visibility:           nullable(STRING)
    }.freeze
    SETTINGS = object(SETTINGS_PROPERTIES).freeze

    # CalendarPreferenceSerializer.
    CALENDAR_SETTINGS = object(SETTINGS_PROPERTIES.merge(scope: STRING, event_type: nullable(STRING))).freeze

    # Preferences::Resolver#resolve_with_sources: the value that applies to
    # each field, and the level it comes from.
    RESOLVED_SETTINGS = object(SETTINGS_PROPERTIES).freeze
    SETTING_SOURCES = object(Preferences::Resolver::PREFERENCE_FIELDS.to_h { |field| [ field, nullable(STRING) ] }).freeze

    # PreferenceParams#generate_preview.
    PREVIEW = object(title: nullable(STRING), description: nullable(STRING), location: nullable(STRING)).freeze

    SAVE_RESULT = { type: "string", enum: %w[saved deleted] }.freeze
  end
end

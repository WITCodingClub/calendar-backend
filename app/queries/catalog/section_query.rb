# frozen_string_literal: true

module Catalog
  # Filters course sections for the public catalog API.
  #
  # Both the REST controllers and the GraphQL schema use this object, so filter
  # behaviour stays identical across the two surfaces. Every filter is optional
  # and unknown values raise FilterError, which callers turn into a 400.
  class SectionQuery
    class FilterError < StandardError; end

    MAX_PER_PAGE     = 200
    DEFAULT_PER_PAGE = 50

    DAYS = Course::MeetingTime.day_of_weeks.freeze

    FILTERS = %i[
      term_uid subject course_number crns pub_ids q schedule_types
      meets_on free_days begins_after ends_before
      credit_hours instructor include_cancelled
    ].freeze

    def initialize(scope = Course.all)
      @scope = scope
    end

    # @return [ActiveRecord::Relation<Course>]
    def call(**filters)
      unknown = filters.keys.map(&:to_sym) - FILTERS
      raise FilterError, "Unknown filter(s): #{unknown.join(', ')}" if unknown.any?

      relation = @scope
      relation = relation.active unless truthy?(filters[:include_cancelled])
      relation = apply_term(relation, filters[:term_uid])
      relation = apply_subject(relation, filters[:subject])
      relation = apply_course_number(relation, filters[:course_number])
      relation = apply_crns(relation, filters[:crns])
      relation = apply_pub_ids(relation, filters[:pub_ids])
      relation = apply_search(relation, filters[:q])
      relation = apply_schedule_types(relation, filters[:schedule_types])
      relation = apply_credit_hours(relation, filters[:credit_hours])
      relation = apply_instructor(relation, filters[:instructor])
      relation = apply_meets_on(relation, filters[:meets_on])
      relation = apply_free_days(relation, filters[:free_days])
      relation = apply_begins_after(relation, filters[:begins_after])
      relation = apply_ends_before(relation, filters[:ends_before])

      relation.order("courses.subject ASC, courses.course_number ASC, courses.section_number ASC")
    end

    # Eager-loads everything the serializers and GraphQL types read.
    def self.with_associations(relation)
      relation.includes(:term, :faculties, :final_exam, meeting_times: { rooms: :building })
    end

    # Converts an "HH:MM", "HHMM", or integer time into the HHMM integer the
    # course_meeting_times columns store.
    def self.parse_time(value)
      return nil if value.blank?

      string = value.to_s.strip
      hhmm =
        case string
        when /\A(\d{1,2}):(\d{2})\z/ then (::Regexp.last_match(1).to_i * 100) + ::Regexp.last_match(2).to_i
        when /\A\d{3,4}\z/           then string.to_i
        else raise FilterError, "Invalid time #{value.inspect}; use HH:MM or HHMM"
        end

      unless hhmm.between?(0, 2359) && (hhmm % 100) < 60
        raise FilterError, "Invalid time #{value.inspect}; use HH:MM or HHMM"
      end

      hhmm
    end

    private

    def apply_term(relation, term_uid)
      return relation if term_uid.blank?

      relation.where(term_id: Term.where(uid: Array(term_uid).map(&:to_i)).select(:id))
    end

    # Accepts either the stored label ("Computer Science (COMP)") or the short
    # code students actually type ("COMP").
    def apply_subject(relation, subject)
      return relation if subject.blank?

      values = Array(subject).map { |s| s.to_s.strip }.reject(&:empty?)
      return relation if values.empty?

      clauses = values.map { "courses.subject = ? OR courses.subject ILIKE ?" }.join(" OR ")
      binds   = values.flat_map { |value| [ value, "%(#{value})" ] }
      relation.where(clauses, *binds)
    end

    def apply_course_number(relation, course_number)
      return relation if course_number.blank?

      relation.where(course_number: Array(course_number).map(&:to_i))
    end

    def apply_crns(relation, crns)
      return relation if crns.blank?

      relation.where(crn: Array(crns).map(&:to_i))
    end

    # The public id is stable and unique across terms, so it needs no term. It
    # is derived from the numeric id, so it is decoded rather than matched.
    def apply_pub_ids(relation, pub_ids)
      return relation if pub_ids.blank?

      values = Array(pub_ids).map { |value| value.to_s.strip }.reject(&:empty?)
      return relation if values.empty?

      ids = values.map do |value|
        Course.id_from_public_id(value) || raise(FilterError, "Unknown pub_id #{value.inspect}")
      end

      relation.where(id: ids)
    end

    def apply_search(relation, query)
      return relation if query.blank?

      term = "%#{sanitize_like(query.to_s.strip)}%"
      relation.where(
        "courses.title ILIKE :q OR courses.subject ILIKE :q OR CAST(courses.course_number AS TEXT) ILIKE :q",
        q: term
      )
    end

    def apply_schedule_types(relation, schedule_types)
      return relation if schedule_types.blank?

      keys = Array(schedule_types).map do |value|
        key = value.to_s.downcase
        key = Course::ScheduleType.key_for_code(value) unless Course::ScheduleType.valid?(key)
        raise FilterError, "Unknown schedule_type #{value.inspect}" if key.blank?

        key
      end

      relation.where(schedule_type: keys)
    end

    def apply_credit_hours(relation, credit_hours)
      return relation if credit_hours.blank?

      relation.where(credit_hours: Array(credit_hours).map(&:to_i))
    end

    def apply_instructor(relation, instructor)
      return relation if instructor.blank?

      term = "%#{sanitize_like(instructor.to_s.strip)}%"
      relation.where(
        id: Course.joins(:faculties).where(
          "faculties.first_name ILIKE :q OR faculties.last_name ILIKE :q OR faculties.display_name ILIKE :q",
          q: term
        ).select(:id)
      )
    end

    # Keeps sections that meet on at least one of the given days.
    def apply_meets_on(relation, days)
      values = day_values(days)
      return relation if values.empty?

      relation.where(id: meeting_times_for_days(values).select(:course_id))
    end

    # Drops sections that meet on any of the given days — "no Friday classes".
    def apply_free_days(relation, days)
      values = day_values(days)
      return relation if values.empty?

      relation.where.not(id: meeting_times_for_days(values).select(:course_id))
    end

    # Drops sections with any meeting starting before the given time.
    def apply_begins_after(relation, time)
      hhmm = self.class.parse_time(time)
      return relation if hhmm.nil?

      relation.where.not(id: Course::MeetingTime.where(begin_time: ...hhmm).select(:course_id))
    end

    # Drops sections with any meeting ending after the given time.
    def apply_ends_before(relation, time)
      hhmm = self.class.parse_time(time)
      return relation if hhmm.nil?

      relation.where.not(id: Course::MeetingTime.where("end_time > ?", hhmm).select(:course_id))
    end

    def meeting_times_for_days(values)
      Course::MeetingTime.where(day_of_week: values)
    end

    def day_values(days)
      Array(days).filter_map do |day|
        next if day.blank?

        key = day.to_s.downcase
        raise FilterError, "Unknown day #{day.inspect}" unless DAYS.key?(key)

        key
      end
    end

    def sanitize_like(value)
      ActiveRecord::Base.sanitize_sql_like(value)
    end

    def truthy?(value)
      ActiveModel::Type::Boolean.new.cast(value).present?
    end
  end
end

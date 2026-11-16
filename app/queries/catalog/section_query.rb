# frozen_string_literal: true

module Catalog
  # Filters course sections for the public catalog API.
  #
  # Both the REST controllers and the GraphQL schema use this object, so filter
  # behaviour stays identical across the two surfaces. Every filter is optional
  # and unknown values raise FilterError, which callers turn into a 400.
  class SectionQuery
    class FilterError < ::Catalog::FilterError; end

    FILTERS = %i[
      term_uid subject course_number crns pub_ids q semantic schedule_types
      meets_on free_days begins_after ends_before
      credit_hours instructor include_cancelled open_only include_waitlist
    ].freeze

    DEFAULT_ORDER = "courses.subject ASC, courses.course_number ASC, courses.section_number ASC"

    def initialize(scope = Course.all)
      @scope = scope
    end

    def call(**filters)
      unknown = filters.keys.map(&:to_sym) - FILTERS
      raise FilterError, "Unknown filter(s): #{unknown.join(', ')}" if unknown.any?

      relation = @scope
      relation = relation.active unless Params.boolean(filters[:include_cancelled])
      relation = apply_term(relation, filters[:term_uid])
      relation = apply_subject(relation, filters[:subject])
      relation = apply_course_number(relation, filters[:course_number])
      relation = apply_crns(relation, filters[:crns])
      relation = apply_pub_ids(relation, filters[:pub_ids])
      relation = apply_schedule_types(relation, filters[:schedule_types])
      relation = apply_credit_hours(relation, filters[:credit_hours])
      relation = apply_instructor(relation, filters[:instructor])
      relation = apply_meets_on(relation, filters[:meets_on])
      relation = apply_free_days(relation, filters[:free_days])
      relation = apply_begins_after(relation, filters[:begins_after])
      relation = apply_ends_before(relation, filters[:ends_before])
      relation = apply_open_only(relation, filters[:open_only], include_waitlist: filters[:include_waitlist])

      # The text filter comes last, because a semantic search ranks whatever
      # the other filters left and replaces the default order.
      apply_text(relation, filters[:q], semantic: Params.boolean(filters[:semantic]))
    end

    # One section by CRN, cancelled or not. term_uid matters when a CRN
    # repeats across terms; without it the lookup takes any term.
    def self.find(crn, term_uid = nil)
      with_associations(new.call(crns: [ crn ], term_uid: term_uid, include_cancelled: true)).first
    end

    def self.find!(crn, term_uid = nil)
      find(crn, term_uid) ||
        raise(ActiveRecord::RecordNotFound, [ "No section with CRN #{crn}", term_uid.presence && "in term #{term_uid}" ].compact.join(" "))
    end

    def self.with_associations(relation)
      relation.includes(:term, { faculties: :rating_distribution }, :final_exam,
                        { section_links: :linked_course }, meeting_times: { rooms: :building })
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

    # Ranks by meaning when the caller asked for it and the vectors are there,
    # and by the literal words otherwise. A semantic search that cannot reach
    # the API falls back to the keyword search rather than failing.
    def apply_text(relation, query, semantic:)
      return relation.order(DEFAULT_ORDER) if query.blank?

      ranked = semantic ? SemanticSearch.ranked_scope(relation, query) : nil
      return ranked if ranked

      apply_search(relation, query).order(DEFAULT_ORDER)
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

    def apply_meets_on(relation, days)
      values = day_values(days)
      return relation if values.empty?

      relation.where(id: meeting_times_for_days(values).select(:course_id))
    end

    def apply_free_days(relation, days)
      values = day_values(days)
      return relation if values.empty?

      relation.where.not(id: meeting_times_for_days(values).select(:course_id))
    end

    def apply_begins_after(relation, time)
      hhmm = Params.time(time)
      return relation if hhmm.nil?

      relation.where.not(id: Course::MeetingTime.where(begin_time: ...hhmm).select(:course_id))
    end

    def apply_ends_before(relation, time)
      hhmm = Params.time(time)
      return relation if hhmm.nil?

      relation.where.not(id: Course::MeetingTime.where("end_time > ?", hhmm).select(:course_id))
    end

    # Keeps sections with a free seat. With include_waitlist, also keeps full
    # sections whose waitlist has room. A section with no seat data
    # (seats_available is null) is left out, because no one knows that it is
    # open. include_waitlist has no effect without open_only.
    def apply_open_only(relation, open_only, include_waitlist:)
      return relation unless Params.boolean(open_only)

      courses = Course.arel_table
      open    = courses[:seats_available].gt(0)
      if Params.boolean(include_waitlist)
        open = open.or(courses[:seats_available].not_eq(nil).and(courses[:waitlist_available].gt(0)))
      end

      relation.where(open)
    end

    def meeting_times_for_days(values)
      Course::MeetingTime.where(day_of_week: values)
    end

    def day_values(days)
      Array(days).compact_blank.map { |day| Params.day(day) }
    end

    def sanitize_like(value)
      ActiveRecord::Base.sanitize_sql_like(value)
    end
  end
end

# frozen_string_literal: true

module CourseOutcomes
  # Stores the outcome of each finished course that the extension reads from
  # the LeopardWeb Student Grades page (PUT /api/user/course_outcomes).
  #
  # Each term in the payload replaces the outcomes of that term: a stored CRN
  # that is not in the payload is removed. A term that is not in the payload
  # does not change. A CRN must belong to a course the user is enrolled in, so
  # the extension processes a term before it sends its outcomes. Other CRNs
  # come back in unknown_crns, and their stored rows do not change.
  class Recorder < ApplicationService
    MAX_TERMS = 30
    MAX_COURSES = 30

    Result = Struct.new(:term, :updated, :unknown_crns, keyword_init: true) do
      def as_json(*) = { term: term.to_s, updated: updated, unknown_crns: unknown_crns }
    end

    attr_reader :user, :entries

    def initialize(user, entries)
      @user = user
      @entries = entries
      super()
    end

    # Returns one Result per term. Raises AcademicProfiles::InvalidProfileError
    # before any write when an entry is not valid.
    def call
      terms = normalize
      by_uid = Term.where(uid: terms.map(&:first)).index_by(&:uid)

      CourseOutcome.transaction do
        terms.map { |uid, courses| record(uid, by_uid[uid], courses) }
      end
    end

    private

    def normalize
      raise invalid("terms must be a non-empty list") unless entries.is_a?(Array) && entries.any?
      raise invalid("terms can have at most #{MAX_TERMS} entries") if entries.size > MAX_TERMS

      seen = Set.new
      entries.each_with_index.map do |entry, index|
        raise invalid("terms[#{index}] must be an object") unless entry.is_a?(Hash)

        entry = entry.with_indifferent_access
        uid = AcademicProfiles::TermCode.parse(entry[:term])
        unless uid
          raise invalid("terms[#{index}].term must be a term code or a term such as \"Fall 2025\"", code: "invalid_term")
        end
        raise invalid("Term #{uid} appears more than once") unless seen.add?(uid)

        [ uid, normalize_courses(entry[:courses], index) ]
      end
    end

    # Returns { crn => outcome }.
    def normalize_courses(courses, index)
      raise invalid("terms[#{index}].courses must be a list") unless courses.is_a?(Array)
      raise invalid("terms[#{index}].courses can have at most #{MAX_COURSES} entries") if courses.size > MAX_COURSES

      courses.each_with_index.to_h do |course, position|
        field = "terms[#{index}].courses[#{position}]"
        raise invalid("#{field} must be an object") unless course.is_a?(Hash)

        course = course.with_indifferent_access
        crn = course[:crn].to_s.strip
        raise invalid("#{field}.crn must be a number") unless crn.match?(/\A\d{1,10}\z/)

        outcome = course[:outcome].to_s
        unless CourseOutcome::OUTCOMES.value?(outcome)
          raise invalid("#{field}.outcome must be one of: #{CourseOutcome::OUTCOMES.values.join(', ')}")
        end

        [ crn.to_i, outcome ]
      end
    end

    def record(uid, term, outcomes)
      enrolled = term ? enrolled_crns(term, outcomes.keys) : []
      unknown = outcomes.keys - enrolled

      # A CRN in the payload keeps its stored row even when it is unknown now:
      # its enrollment can be missing for a short time, for example while the
      # extension reprocesses the term.
      user.course_outcomes.where(term_uid: uid).where.not(crn: outcomes.keys).delete_all

      rows = enrolled.map { |crn| { user_id: user.id, term_uid: uid, crn: crn, outcome: outcomes.fetch(crn) } }
      # normalize_courses checked each outcome before this write.
      CourseOutcome.upsert_all(rows, unique_by: %i[user_id term_uid crn], record_timestamps: true) if rows.any? # rubocop:disable Rails/SkipsModelValidations

      Result.new(term: uid, updated: enrolled.size, unknown_crns: unknown.map(&:to_s))
    end

    # The CRNs of the term that the user is enrolled in.
    def enrolled_crns(term, crns)
      Course.where(term: term, crn: crns).where(id: user.enrollments.select(:course_id)).pluck(:crn)
    end

    def invalid(message, code: "invalid_outcome")
      AcademicProfiles::InvalidProfileError.new(message, code: code)
    end
  end
end

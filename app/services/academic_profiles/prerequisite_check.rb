# frozen_string_literal: true

module AcademicProfiles
  # Walks the prerequisite tree of a CatalogCourse
  # (Catalog::CourseDetailsParser) against the courses that count. It gives
  # the status of the tree and the courses not met under it.
  # NextTermCourses (#449, #996) and PlanEstimate (#1011) use it.
  class PrerequisiteCheck
    # A prerequisite tree node is met, not met, or unknown (a test score).
    MET = "met"
    NOT_MET = "not_met"
    UNKNOWN = "unknown"

    # courses: answers counted(key) with the outcomes of the courses that
    # count for a [subject, number] key: [] when none counts, nil for a
    # course with no outcome, or a CourseOutcome outcome.
    def initialize(courses, course_keys)
      @courses = courses
      @course_keys = course_keys
    end

    # { status:, missing:, missing_keys: } of one prerequisite tree node.
    # missing is the text for a reader, such as "WDGT 1100 or WDGT 1200".
    # missing_keys is every course key under it.
    def call(node)
      case node["type"]
      when "and", "or"
        results = node["operands"].map { |operand| call(operand) }
        status = node["type"] == "and" ? all_status(results.pluck(:status)) : any_status(results.pluck(:status))
        return { status: status, missing: [], missing_keys: [] } if status == MET

        { status: status, missing: missing_of(node["type"], results), missing_keys: results.flat_map { |result| result[:missing_keys] }.uniq }
      when "course"
        key = [ node["subject_code"], node["course_number"].to_i ]
        status = course_status(key, node["min_grade"])
        status == MET ? { status: status, missing: [], missing_keys: [] } : { status: status, missing: [ CourseKeys.format(key) ], missing_keys: [ key ] }
      else
        { status: UNKNOWN, missing: [], missing_keys: [] }
      end
    end

    private

    def all_status(statuses)
      if statuses.all?(MET) then MET
      elsif statuses.include?(NOT_MET) then NOT_MET
      else UNKNOWN
      end
    end

    def any_status(statuses)
      if statuses.include?(MET) then MET
      elsif statuses.all?(NOT_MET) then NOT_MET
      else UNKNOWN
      end
    end

    # The options of an or are one entry, such as "WDGT 1100 or WDGT 1200",
    # so a reader does not think it needs both.
    def missing_of(type, results)
      lists = results.map { |result| result[:missing] }.reject(&:empty?)
      return lists.flatten.uniq if type == "and"

      lists.map { |list| list.size == 1 ? list.first : "(#{list.join(' and ')})" }.uniq.then do |options|
        options.size > 1 ? [ options.join(" or ") ] : options
      end
    end

    # met when a course that counts is the course or an alias of it, with a
    # grade the minimum allows. Outcomes say only "C or better" or "passed
    # below C", so a minimum above C is unknown.
    def course_status(key, min_grade)
      outcomes = @course_keys.equivalents(key).flat_map { |found| @courses.counted(found) }
      return NOT_MET if outcomes.empty?

      grade = min_grade.to_s.strip.upcase
      return MET if grade.empty? || grade.start_with?("D")
      return UNKNOWN unless grade.start_with?("C")

      outcomes.any? { |outcome| outcome != CourseOutcome::PASSED_BELOW_C } ? MET : NOT_MET
    end
  end
end

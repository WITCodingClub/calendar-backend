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

    # courses: the courses that count, by [subject, number]. It answers
    # fetch(pair, []) with a list of hashes with an :outcome key (nil, or a
    # CourseOutcome outcome). aliases: each pair with its old and new pairs.
    def initialize(courses, aliases)
      @courses = courses
      @aliases = aliases
    end

    # { status:, missing: } of one prerequisite tree node.
    def call(node)
      case node["type"]
      when "and", "or"
        results = node["operands"].map { |operand| call(operand) }
        statuses = results.pluck(:status)
        status = if node["type"] == "and"
          if statuses.all?(MET) then MET
          elsif statuses.include?(NOT_MET) then NOT_MET
          else UNKNOWN
          end
        elsif statuses.include?(MET) then MET
        elsif statuses.all?(NOT_MET) then NOT_MET
        else UNKNOWN
        end
        { status: status, missing: status == MET ? [] : missing_of(node["type"], results) }
      when "course"
        code = "#{node['subject_code']} #{node['course_number']}"
        status = course_status(node["subject_code"], node["course_number"].to_i, node["min_grade"])
        { status: status, missing: status == MET ? [] : [ code ] }
      else
        { status: UNKNOWN, missing: [] }
      end
    end

    private

    # The missing courses of an and or an or node. The options of an or
    # are one entry, such as "WDGT 1100 or WDGT 1200", so a reader does not
    # think it needs both.
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
    def course_status(subject, number, min_grade)
      keys = [ [ subject, number ], *@aliases.fetch([ subject, number ], []) ]
      courses = keys.flat_map { |key| @courses.fetch(key, []) }
      return NOT_MET if courses.empty?

      grade = min_grade.to_s.strip.upcase
      return MET if grade.empty? || grade.start_with?("D")
      return UNKNOWN unless grade.start_with?("C")

      courses.any? { |course| course[:outcome] != "passed_below_c" } ? MET : NOT_MET
    end
  end
end

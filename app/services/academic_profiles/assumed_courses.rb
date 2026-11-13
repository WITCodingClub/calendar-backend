# frozen_string_literal: true

module AcademicProfiles
  # The courses that NextTermCourses counts as passed before the term (#996),
  # in addition to the courses done or in progress:
  # - codes: the course codes of the assume argument.
  # - plans: when true, the courses of the saved registration plans (#995)
  #   for the terms after the current term and before the term. The
  #   enrollments of the current term and of earlier terms are the real
  #   record, so a plan for one of those terms does not count. Without a
  #   current term, no plan counts.
  #
  # skip tells which [subject, number] pairs to leave out: the courses the
  # student already did or takes with a C or better.
  class AssumedCourses
    MAX_CODES = 50

    class InvalidCodesError < StandardError; end

    # The [subject, number] pairs of an assume argument: a string of codes
    # separated by commas ("COMP3350,MATH 2300"), or a list of such strings.
    # Raises InvalidCodesError for a value that is not a course code, or for
    # more than MAX_CODES codes.
    def self.parse(value)
      return [] if value.nil?
      unless value.is_a?(String) || (value.is_a?(Array) && value.all?(String))
        raise InvalidCodesError, "assume must be course codes such as COMP3350, separated by commas"
      end

      codes = Array(value).flat_map { |entry| entry.split(",") }.map(&:strip).reject(&:empty?)
      raise InvalidCodesError, "assume takes at most #{MAX_CODES} course codes" if codes.size > MAX_CODES

      codes.map do |code|
        CatalogCourse.parse_code(code) ||
          raise(InvalidCodesError, "assume must be course codes such as COMP3350, separated by commas")
      end.uniq
    end

    def initialize(user, term_uid:, current_term_uid:, codes: [], plans: false, skip: ->(_pair) { false })
      @user = user
      @term_uid = term_uid
      @current_term_uid = current_term_uid
      @codes = codes
      @plans = plans
      @skip = skip
    end

    # True when the caller asked for assumed courses, also when none is left.
    def requested?
      @codes.any? || @plans
    end

    # The assumed [subject, number] pairs, each one time, sorted.
    def pairs
      @pairs ||= (@codes + plan_pairs.values.flatten(1)).uniq.reject { |pair| @skip.call(pair) }.sort
    end

    # The terms of the plans that gave at least one assumed course.
    def from_plans
      plan_pairs.select { |_uid, list| list.intersect?(pairs) }.keys
    end

    def to_h
      { courses: pairs.map { |subject, number| "#{subject} #{number}" }, from_plans: from_plans }
    end

    private

    # { term_uid => pairs } of the saved plans, oldest term first. The
    # client sends the codes of a plan, so a code that does not parse is
    # skipped.
    def plan_pairs
      @plan_pairs ||= if @plans && @term_uid && @current_term_uid
        RegistrationPlan.where(user: @user, term_uid: (@current_term_uid + 1)...@term_uid).order(:term_uid).pluck(:term_uid, :courses).to_h do |uid, courses|
          [ uid, Array(courses).filter_map { |course| course.is_a?(Hash) && CatalogCourse.parse_code(course["code"]) } ]
        end
      else
        {}
      end
    end
  end
end

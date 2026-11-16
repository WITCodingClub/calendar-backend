# frozen_string_literal: true

module AcademicProfiles
  # The arguments of GET /api/user/next_term_courses and of the MCP tool
  # my_next_term_courses, checked once for both (NextTermCourses).
  class NextTermRequest
    class InvalidTermError < PlanningError; end

    # term: a Banner code or a label, or blank for the default term. assume:
    # course codes (AssumedCourses.parse). Raises PlanningError for a bad
    # value.
    def initialize(term:, assume:, assume_plans:, include_candidates:)
      @term_uid = parse_term(term)
      @assume = AssumedCourses.parse(assume)
      @assume_plans = assume_plans
      @include_candidates = include_candidates
    end

    def call(user)
      NextTermCourses.new(user, term_uid: @term_uid, assume: @assume, assume_plans: @assume_plans,
                                include_candidates: @include_candidates).call
    end

    private

    def parse_term(term)
      return nil if term.blank?

      TermCode.parse(term.to_s) ||
        raise(InvalidTermError, "term must be a Banner term code or a label such as Spring 2027")
    end
  end
end

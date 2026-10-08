# frozen_string_literal: true

module Brightspace
  # Filters and orders assignments for the list routes. Every filter reads the
  # user's own data: progress comes from the user's preference, and due_before
  # compares the effective deadline.
  class AssignmentQuery
    def initialize(scope, status: nil, due_before: nil)
      @scope      = scope
      @status     = status
      @due_before = due_before
    end

    def call
      scope = @scope.not_removed.by_effective_due_at.includes(:preference, :course_offering)

      if @status.present?
        unless Brightspace::AssignmentPreference::PROGRESSES.include?(@status)
          raise ActionController::BadRequest, "status must be one of #{Brightspace::AssignmentPreference::PROGRESSES.join(', ')}"
        end

        scope = scope.where("COALESCE(brightspace_assignment_preferences.progress, 'not_started') = ?", @status)
      end

      if @due_before.present?
        scope = scope.where("#{Brightspace::Assignment::EFFECTIVE_DUE_AT_SQL} < ?", parse_time(@due_before))
      end

      scope
    end

    # The next deadline of each class that is not done, as
    # { course_offering_id => assignment }.
    def self.next_deadlines(course_offering_ids, now: Time.current)
      return {} if course_offering_ids.empty?

      Brightspace::Assignment.not_removed.with_preferences
                             .where(course_offering_id: course_offering_ids)
                             .where("#{Brightspace::Assignment::EFFECTIVE_DUE_AT_SQL} >= ?", now)
                             .where("COALESCE(brightspace_assignment_preferences.progress, 'not_started') <> 'done'")
                             .select("DISTINCT ON (brightspace_assignments.course_offering_id) brightspace_assignments.*")
                             .order(Arel.sql("brightspace_assignments.course_offering_id, #{Brightspace::Assignment::EFFECTIVE_DUE_AT_SQL}, brightspace_assignments.id"))
                             .includes(:preference)
                             .index_by(&:course_offering_id)
    end

    private

    def parse_time(value)
      Time.iso8601(value.to_s)
    rescue ArgumentError
      raise ActionController::BadRequest, "due_before must be an ISO 8601 time"
    end
  end
end

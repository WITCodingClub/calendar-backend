# frozen_string_literal: true

module Brightspace
  # A Brightspace class for the class list. It can link to a registration
  # course, but it does not replace the processed schedule.
  class ClassSerializer
    def initialize(offering, connection:, next_deadline: nil)
      @offering      = offering
      @connection    = connection
      @next_deadline = next_deadline
    end

    def as_json(*)
      {
        id:            @offering.public_id,
        source_id:     @offering.source_id,
        course_id:     @offering.course&.public_id,
        term:          TermSerializer.new(@offering.term).as_json,
        title:         @offering.title,
        next_deadline: next_deadline_json,
        version:       @offering.version,
        sync:          sync_json
      }
    end

    private

    def next_deadline_json
      return nil unless @next_deadline

      {
        assignment_id:    @next_deadline.public_id,
        kind:             @next_deadline.kind,
        title:            @next_deadline.title,
        effective_due_at: @next_deadline.effective_due_at&.utc&.iso8601
      }
    end

    def sync_json
      states = Brightspace::SECTIONS.map { |section| @offering.section_state(section) }

      {
        last_synced_at:    @connection&.last_synced_at&.utc&.iso8601,
        last_collected_at: states.filter_map { |state| state["collected_at"] }.max,
        has_errors:        states.any? { |state| state["error"].present? }
      }
    end
  end
end

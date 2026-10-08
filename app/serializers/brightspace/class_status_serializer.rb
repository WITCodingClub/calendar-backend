# frozen_string_literal: true

module Brightspace
  # How fresh each section of one class is: when the last successful
  # collection was, and the error of the last failed one.
  class ClassStatusSerializer
    def initialize(offering)
      @offering = offering
    end

    def as_json(*)
      {
        id:        @offering.public_id,
        source_id: @offering.source_id,
        title:     @offering.title,
        version:   @offering.version,
        sections:  Brightspace::SECTIONS.index_with { |section| section_json(@offering.section_state(section)) }
      }
    end

    private

    def section_json(state)
      {
        last_collected_at: state["collected_at"],
        complete:          state.fetch("complete", false),
        error:             state["error"],
        failed_at:         state["failed_at"]
      }
    end
  end
end

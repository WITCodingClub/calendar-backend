# frozen_string_literal: true

module Types
  class SectionFilterInput < BaseInputObject
    description "Filters for the sections query. Every field is optional."

    argument :term_uid, Integer, required: false
    argument :subject, [ String ], required: false,
             description: "Subject label or short code, e.g. \"COMP\""
    argument :course_number, [ Integer ], required: false
    argument :crns, [ Integer ], required: false
    argument :pub_ids, [ String ], required: false,
             description: "Public ids, which stay unique across terms"
    argument :q, String, required: false, description: "Free text over title, subject, and number"
    argument :semantic, Boolean, required: false, default_value: false,
             description: "Rank q by meaning instead of by the literal words. " \
                          "Falls back to the literal match when semantic search is off."
    argument :schedule_types, [ ScheduleTypeEnum ], required: false
    argument :meets_on, [ DayOfWeekEnum ], required: false,
             description: "Keep sections meeting on at least one of these days"
    argument :free_days, [ DayOfWeekEnum ], required: false,
             description: "Drop sections meeting on any of these days"
    argument :begins_after, String, required: false,
             description: "Drop sections with any meeting before this time (HH:MM)"
    argument :ends_before, String, required: false,
             description: "Drop sections with any meeting ending after this time (HH:MM)"
    argument :credit_hours, [ Integer ], required: false
    argument :instructor, String, required: false
    argument :include_cancelled, Boolean, required: false, default_value: false

    def to_query_filters
      to_h.compact
    end
  end
end

# frozen_string_literal: true

module Types
  class ScheduleCheckType < BaseObject
    description "The result of checking a set of sections together (Catalog::ScheduleCheck)"

    field :term, TermType, null: false
    field :sections, [ ScheduleSectionType ], null: false
    field :not_found, [ Integer ], null: false, description: "CRNs that are not in the term"
    field :cancelled, [ Integer ], null: false
    field :conflicts, [ ScheduleConflictType ], null: false
    field :link_problems, [ ScheduleLinkProblemType ], null: false
    field :duplicates, [ ScheduleDuplicateType ], null: false
    field :totals, ScheduleTotalsType, null: false

    def term = Term.find_by!(uid: object[:term][:uid])
  end
end

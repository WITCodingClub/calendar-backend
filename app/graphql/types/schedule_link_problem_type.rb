# frozen_string_literal: true

module Types
  class ScheduleLinkProblemType < BaseObject
    description "A linked section (a lecture or its lab) that the schedule cannot register as it is"

    field :crn, Integer, null: false
    field :problem, String, null: false,
          description: "\"missing_partner\": add every CRN of one partnerOptions set. " \
                       "\"unverified_link\": Banner's pairs are not stored yet and no partner is known; " \
                       "check it in LeopardWeb."
    field :message, String, null: false
    field :source, String, null: false, description: "\"banner\" or \"link_identifier\", as in LinkedSections"
    field :partner_crns, [ Integer ], null: false
    field :partner_options, [ [ Integer ] ], null: false
  end
end

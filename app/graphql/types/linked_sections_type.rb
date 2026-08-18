# frozen_string_literal: true

module Types
  class LinkedSectionsType < BaseObject
    description "Sections that Banner requires a student to register together, " \
                "most often a lecture and its lab."

    field :required, Boolean, null: false,
          description: "True when Banner marks this section as part of a pairing."
    field :identifier, String, null: true,
          description: "Banner's link identifier, e.g. \"A1\" for a lecture and \"B1\" for its labs."
    field :crns, [ Integer ], null: false,
          description: "CRNs of the partner sections in the same term. Empty when the section stands alone."
    field :pub_ids, [ String ], null: false,
          description: "Public ids of the same partner sections, in the same order as crns."
  end
end

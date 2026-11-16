# frozen_string_literal: true

module Types
  class SectionFilterInput < BaseInputObject
    description "Filters for the sections query. Every field is optional."

    CatalogFilterArguments.define(self, ::Catalog::SectionQuery)
  end
end

# frozen_string_literal: true

module TwentyFiveLive
  class OrganizationCustomAttribute
    attr_reader :id, :name, :attribute_type, :attribute_type_name, :sort_order, :defn_state

    def initialize(id:, name:, attribute_type:, attribute_type_name:, sort_order:, defn_state:)
      @id                 = id
      @name               = name
      @attribute_type     = attribute_type
      @attribute_type_name = attribute_type_name
      @sort_order         = sort_order
      @defn_state         = defn_state
    end

    def active?
      defn_state == 1
    end

    def to_s
      name
    end

    ORGANIZATION_CUSTOM_ATTRIBUTES = [
      { attribute_id:  5, attribute_name: "Email Address",          attribute_type: "S", attribute_type_name: "String",       sort_order: 1, defn_state: 1 },
      { attribute_id:  6, attribute_name: "Engage Organization ID", attribute_type: "S", attribute_type_name: "String",       sort_order: 2, defn_state: 1 },
      { attribute_id: -11, attribute_name: "X25 CIP Code",          attribute_type: "S", attribute_type_name: "String",       sort_order: 3, defn_state: 0 },
      { attribute_id: -8,  attribute_name: "X25 College",           attribute_type: "2", attribute_type_name: "Organization", sort_order: 4, defn_state: 0 }
    ].freeze

    def self.find_by_id(id)
      raw = ORGANIZATION_CUSTOM_ATTRIBUTES.find { |a| a[:attribute_id] == id }
      return nil unless raw

      new(id: raw[:attribute_id], name: raw[:attribute_name],
          attribute_type: raw[:attribute_type], attribute_type_name: raw[:attribute_type_name],
          sort_order: raw[:sort_order], defn_state: raw[:defn_state])
    end

    def self.all
      ORGANIZATION_CUSTOM_ATTRIBUTES.map do |a|
        new(id: a[:attribute_id], name: a[:attribute_name],
            attribute_type: a[:attribute_type], attribute_type_name: a[:attribute_type_name],
            sort_order: a[:sort_order], defn_state: a[:defn_state])
      end
    end
  end
end

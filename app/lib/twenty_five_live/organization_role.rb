# frozen_string_literal: true

module TwentyFiveLive
  class OrganizationRole
    attr_reader :id, :name, :sort_order, :defn_state

    def initialize(id:, name:, sort_order:, defn_state:)
      @id         = id
      @name       = name
      @sort_order = sort_order
      @defn_state = defn_state
    end

    def active?
      defn_state == 1
    end

    def to_s
      name
    end

    ORGANIZATION_ROLES = [
      { role_id:  4, role_name: "Athletics Assistant Coach", sort_order: 1, defn_state: 1 },
      { role_id:  3, role_name: "Athletics Coach",           sort_order: 2, defn_state: 1 },
      { role_id: -1, role_name: "Billing Contact",           sort_order: 3, defn_state: 1 },
      { role_id:  2, role_name: "Scheduling Contact",        sort_order: 4, defn_state: 1 },
      { role_id: -2, role_name: "No Role",                   sort_order: 5, defn_state: 1 }
    ].freeze

    def self.find_by_id(id)
      raw = ORGANIZATION_ROLES.find { |r| r[:role_id] == id }
      return nil unless raw

      new(id: raw[:role_id], name: raw[:role_name],
          sort_order: raw[:sort_order], defn_state: raw[:defn_state])
    end

    def self.all
      ORGANIZATION_ROLES.map do |r|
        new(id: r[:role_id], name: r[:role_name],
            sort_order: r[:sort_order], defn_state: r[:defn_state])
      end
    end
  end
end

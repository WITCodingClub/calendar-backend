# frozen_string_literal: true

module TwentyFiveLive
  class OrganizationType
    attr_reader :id, :name, :sort_order, :defn_state, :rate_group_id, :rate_group_name

    def initialize(id:, name:, sort_order:, defn_state:, rate_group_id:, rate_group_name:)
      @id              = id
      @name            = name
      @sort_order      = sort_order
      @defn_state      = defn_state
      @rate_group_id   = rate_group_id
      @rate_group_name = rate_group_name
    end

    def active?
      defn_state == 1
    end

    def internal?
      rate_group_name == "Internal"
    end

    def to_s
      name
    end

    ORGANIZATION_TYPES = [
      { type_id: 10, type_name: "Room Optimization",      sort_order: 1, defn_state: 1, rate_group_id: 2, rate_group_name: "Internal"   },
      { type_id:  9, type_name: "Academic",               sort_order: 2, defn_state: 1, rate_group_id: 2, rate_group_name: "Internal"   },
      { type_id:  2, type_name: "Administrative",         sort_order: 3, defn_state: 1, rate_group_id: 2, rate_group_name: "Internal"   },
      { type_id:  3, type_name: "Athletics",              sort_order: 4, defn_state: 1, rate_group_id: 2, rate_group_name: "Internal"   },
      { type_id:  4, type_name: "External (For-Profit)",  sort_order: 5, defn_state: 1, rate_group_id: 3, rate_group_name: "For-Profit" },
      { type_id:  5, type_name: "External (Non-Profit)",  sort_order: 6, defn_state: 1, rate_group_id: 4, rate_group_name: "Non-Profit" },
      { type_id:  6, type_name: "Government / Community", sort_order: 7, defn_state: 1, rate_group_id: 4, rate_group_name: "Non-Profit" },
      { type_id:  7, type_name: "Student Groups",         sort_order: 8, defn_state: 1, rate_group_id: 2, rate_group_name: "Internal"   },
      { type_id:  8, type_name: "Subject Code",           sort_order: 9, defn_state: 1, rate_group_id: nil, rate_group_name: nil         },
    ].freeze

    def self.find_by_id(id)
      raw = ORGANIZATION_TYPES.find { |t| t[:type_id] == id }
      return nil unless raw

      new(id: raw[:type_id], name: raw[:type_name], sort_order: raw[:sort_order],
          defn_state: raw[:defn_state], rate_group_id: raw[:rate_group_id],
          rate_group_name: raw[:rate_group_name])
    end

    def self.all
      ORGANIZATION_TYPES.map do |t|
        new(id: t[:type_id], name: t[:type_name], sort_order: t[:sort_order],
            defn_state: t[:defn_state], rate_group_id: t[:rate_group_id],
            rate_group_name: t[:rate_group_name])
      end
    end
  end
end

# frozen_string_literal: true

module TwentyFiveLive
  class OrganizationRating
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

    ORGANIZATION_RATINGS = [
      { rating_id: 2, rating_name: "Do Not Allow Bookings", sort_order: 1, defn_state: 1 },
      { rating_id: 3, rating_name: "Inactive or Frozen",    sort_order: 2, defn_state: 1 },
      { rating_id: 4, rating_name: "On Probation",          sort_order: 3, defn_state: 1 },
      { rating_id: 5, rating_name: "Pay In Advance",        sort_order: 4, defn_state: 1 }
    ].freeze

    def self.find_by_id(id)
      raw = ORGANIZATION_RATINGS.find { |r| r[:rating_id] == id }
      return nil unless raw

      new(id: raw[:rating_id], name: raw[:rating_name],
          sort_order: raw[:sort_order], defn_state: raw[:defn_state])
    end

    def self.all
      ORGANIZATION_RATINGS.map do |r|
        new(id: r[:rating_id], name: r[:rating_name],
            sort_order: r[:sort_order], defn_state: r[:defn_state])
      end
    end
  end
end

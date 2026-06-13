module TwentyFiveLive
  class EventRequirement
    attr_reader :id, :name, :requirement_type, :requirement_type_name,
                :stock_count, :allow_comment, :sort_order, :defn_state

    def initialize(id:, name:, requirement_type:, requirement_type_name:,
                   stock_count:, allow_comment:, sort_order:, defn_state:)
      @id = id
      @name = name
      @requirement_type = requirement_type
      @requirement_type_name = requirement_type_name
      @stock_count = stock_count
      @allow_comment = allow_comment
      @sort_order = sort_order
      @defn_state = defn_state
    end

    def active?
      defn_state == 1
    end

    def comment_allowed?
      allow_comment == 1
    end

    def infinite_stock?
      stock_count == -1
    end

    EVENT_REQUIREMENTS = [].freeze

    def self.find_by_id(id)
      raw = EVENT_REQUIREMENTS.find { |r| r[:requirement_id] == id }
      return nil unless raw

      new(
        id: raw[:requirement_id],
        name: raw[:requirement_name],
        requirement_type: raw[:requirement_type],
        requirement_type_name: raw[:requirement_type_name],
        stock_count: raw[:stock_count],
        allow_comment: raw[:allow_comment],
        sort_order: raw[:sort_order],
        defn_state: raw[:defn_state]
      )
    end
  end
end

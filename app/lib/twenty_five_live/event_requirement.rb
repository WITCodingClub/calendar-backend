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
  end

  EVENT_REQUIREMENTS = [
    {
      requirement_id: 10,
      requirement_name: "Event Review - Student Life",
      requirement_type: 6,
      requirement_type_name: "Other",
      stock_count: 0,
      allow_comment: 1,
      sort_order: 1,
      defn_state: 1
    },
    {
      requirement_id: 9,
      requirement_name: "Event Review - Media",
      requirement_type: 6,
      requirement_type_name: "Other",
      stock_count: -1,
      allow_comment: 1,
      sort_order: 2,
      defn_state: 1
    },
    {
      requirement_id: 8,
      requirement_name: "Event Review - WITPD",
      requirement_type: 6,
      requirement_type_name: "Other",
      stock_count: -1,
      allow_comment: 1,
      sort_order: 3,
      defn_state: 1
    },
    {
      requirement_id: 7,
      requirement_name: "Expected Attendance Over 200",
      requirement_type: 6,
      requirement_type_name: "Other",
      stock_count: 0,
      allow_comment: 1,
      sort_order: 4,
      defn_state: 1
    },
    {
      requirement_id: 6,
      requirement_name: "Notification: Movie License",
      requirement_type: 6,
      requirement_type_name: "Other",
      stock_count: -1,
      allow_comment: 1,
      sort_order: 5,
      defn_state: 1
    },
    {
      requirement_id: 4,
      requirement_name: "Notification: Business Services",
      requirement_type: 6,
      requirement_type_name: "Other",
      stock_count: -1,
      allow_comment: 0,
      sort_order: 6,
      defn_state: 1
    },
    {
      requirement_id: 2,
      requirement_name: "Notification: Alcohol - Dean of Students",
      requirement_type: 6,
      requirement_type_name: "Other",
      stock_count: -1,
      allow_comment: 0,
      sort_order: 7,
      defn_state: 1
    }
  ].freeze

  def self.event_requirement_by_id(id)
    raw = EVENT_REQUIREMENTS.find { |r| r[:requirement_id] == id }
    return nil unless raw

    EventRequirement.new(
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

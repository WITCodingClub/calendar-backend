module TwentyFiveLive
  class EventRole
    attr_reader :id, :name, :sort_order, :defn_state, :tags

    def initialize(id:, name:, sort_order:, defn_state:, tags: [])
      @id = id
      @name = name
      @sort_order = sort_order
      @defn_state = defn_state
      @tags = tags
    end

    def active?
      defn_state == 1
    end

    def requestor?
      name == "Requestor"
    end

    def has_tag?(tag_name)
      tags.any? { |t| t[:tag_name] == tag_name }
    end


    EVENT_ROLES = [
      {
        role_id: 5,
        role_name: "Event Organizer",
        sort_order: 1,
        defn_state: 1,
        tags: []
      },
      {
        role_id: -1,
        role_name: "Requestor",
        sort_order: 2,
        defn_state: 1,
        tags: [
          { tag_id: 15, tag_name: "Event Role - Requestor Only" },
          { tag_id: 16, tag_name: "Campus Group Functions" }
        ]
      },
      {
        role_id: -2,
        role_name: "Scheduler",
        sort_order: 3,
        defn_state: 1,
        tags: []
      },
      {
        role_id: -3,
        role_name: "Instructor",
        sort_order: 4,
        defn_state: 1,
        tags: []
      },
      {
        role_id: 2,
        role_name: "Additional Contact",
        sort_order: 5,
        defn_state: 1,
        tags: []
      },
      {
        role_id: 3,
        role_name: "Day Of Contact",
        sort_order: 6,
        defn_state: 1,
        tags: [
          { tag_id: 16, tag_name: "Campus Group Functions" }
        ]
      },
      {
        role_id: 4,
        role_name: "Center Advisor (Club/Org)",
        sort_order: 7,
        defn_state: 1,
        tags: [
          { tag_id: 16, tag_name: "Campus Group Functions" }
        ]
      }
    ].freeze

    def self.event_role_by_id(id)
      raw = EVENT_ROLES.find { |r| r[:role_id] == id }
      return nil unless raw

      EventRole.new(
        id: raw[:role_id],
        name: raw[:role_name],
        sort_order: raw[:sort_order],
        defn_state: raw[:defn_state],
        tags: raw[:tags]
      )
    end
  end
end

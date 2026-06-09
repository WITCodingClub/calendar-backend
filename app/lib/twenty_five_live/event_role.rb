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


    EVENT_ROLES = [].freeze

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

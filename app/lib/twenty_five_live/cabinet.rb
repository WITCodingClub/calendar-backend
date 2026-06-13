module TwentyFiveLive
  class Cabinet
    attr_reader :key, :id, :name, :event_type_name

    def initialize(key:, id:, name:, event_type_name:)
      @key = key
      @id  = id
      @name = name
      @event_type_name = event_type_name
    end

    def academics?
      event_type_name == "Academics"
    end

    CABINETS = {
      courses: {
        id: 10,
        name: "Courses",
        event_type_name: "Academics"
      },
      events: {
        id: 15,
        name: "Events",
        event_type_name: "Events"
      }
    }.freeze


    def self.cabinet(key)
      raw = CABINETS.fetch(key)
      Cabinet.new(
        key: key,
        id: raw[:id],
        name: raw[:name],
        event_type_name: raw[:event_type_name]
      )
    end
  end
end

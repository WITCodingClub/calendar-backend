# frozen_string_literal: true

module TwentyFiveLive
  class SpaceCustomAttribute
    SPACE_CUSTOM_ATTRIBUTES = [
      { attribute_id: 2,   attribute_name: "HVAC Zone",              defn_state: 1 },
      { attribute_id: 3,   attribute_name: "Phone Number",           defn_state: 1 },
      { attribute_id: 4,   attribute_name: "Serviced by Elevator",   defn_state: 1 },
      { attribute_id: -3,  attribute_name: "Map",                    defn_state: 2 },
      { attribute_id: -6,  attribute_name: "X25 Building",           defn_state: 2 },
      { attribute_id: -7,  attribute_name: "X25 Owner Organization", defn_state: 2 },
      { attribute_id: -9,  attribute_name: "X25 Room Use Code",      defn_state: 1 },
      { attribute_id: -10, attribute_name: "X25 Floor Number",       defn_state: 2 },
      { attribute_id: -12, attribute_name: "X25 Assignable Area",    defn_state: 1 },
      { attribute_id: -14, attribute_name: "Latitude",               defn_state: 1 },
      { attribute_id: -15, attribute_name: "Longitude",              defn_state: 1 },
      { attribute_id: -81, attribute_name: "WDYT Location Survey",   defn_state: 2 }
    ].freeze
  end
end

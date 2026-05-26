# frozen_string_literal: true

module TwentyFiveLive
  class EventCustomAttribute < ApplicationRecord
    self.table_name = "twenty_five_live_event_custom_attributes"

    include EncodedIds::HashidIdentifiable

    set_public_id_prefix :eca

    validates :twenty_five_live_id, presence: true, uniqueness: true
    validates :name, presence: true

    def active?
      defn_state == 1
    end

    def multivalue?
      multi_val == "T"
    end

    def to_param
      public_id
    end

    EVENT_CUSTOM_ATTRIBUTES = [
      { attribute_id: 36,     attribute_name: "Is this event AI related?",                                         attribute_type: "B", attribute_type_name: "Boolean",       multi_val: nil, sort_order: 1,  defn_state: 1 },
      { attribute_id: -10001, attribute_name: "CRM Pool ID",                                                       attribute_type: "N", attribute_type_name: "Integer",       multi_val: "F", sort_order: 2,  defn_state: 1 },
      { attribute_id: 34,     attribute_name: "Panopto Webinar URL",                                               attribute_type: "R", attribute_type_name: "File Reference", multi_val: nil, sort_order: 3,  defn_state: 1 },
      { attribute_id: 32,     attribute_name: "Should this event appear on the public university website? (wit.edu)", attribute_type: "B", attribute_type_name: "Boolean",    multi_val: nil, sort_order: 4,  defn_state: 1 },
      { attribute_id: 29,     attribute_name: "Academic Term",                                                     attribute_type: "S", attribute_type_name: "String",        multi_val: nil, sort_order: 5,  defn_state: 1 },
      { attribute_id: 28,     attribute_name: "Featured Event",                                                    attribute_type: "S", attribute_type_name: "String",        multi_val: nil, sort_order: 6,  defn_state: 1 },
      { attribute_id: 27,     attribute_name: "WITSync Correlation ID",                                            attribute_type: "X", attribute_type_name: "Long Text",     multi_val: nil, sort_order: 7,  defn_state: 1 },
      { attribute_id: 26,     attribute_name: "Is your event fake? (Just for training, remove it later)",          attribute_type: "B", attribute_type_name: "Boolean",       multi_val: nil, sort_order: 8,  defn_state: 0 },
      { attribute_id: 25,     attribute_name: "Who is the intended audience for this event?",                      attribute_type: "S", attribute_type_name: "String",        multi_val: "T", sort_order: 9,  defn_state: 1 },
      { attribute_id: 19,     attribute_name: "Will non-Wentworth affiliated minors be attending this event?",     attribute_type: "B", attribute_type_name: "Boolean",       multi_val: nil, sort_order: 10, defn_state: 1 },
      { attribute_id: 18,     attribute_name: "Will you be providing food or beverages at your event?",            attribute_type: "B", attribute_type_name: "Boolean",       multi_val: nil, sort_order: 11, defn_state: 1 },
      { attribute_id: 20,     attribute_name: "Will alcohol be served at this event?",                             attribute_type: "B", attribute_type_name: "Boolean",       multi_val: nil, sort_order: 12, defn_state: 1 },
      { attribute_id: 30,     attribute_name: "What type of alcohol will be served?",                              attribute_type: "S", attribute_type_name: "String",        multi_val: "T", sort_order: 13, defn_state: 1 },
      { attribute_id: 31,     attribute_name: "How will the alcohol be distributed?",                              attribute_type: "S", attribute_type_name: "String",        multi_val: "T", sort_order: 14, defn_state: 1 },
      { attribute_id: 21,     attribute_name: "Do you plan to contract with any outside vendors to support your event?", attribute_type: "B", attribute_type_name: "Boolean", multi_val: nil, sort_order: 15, defn_state: 1 },
      { attribute_id: 22,     attribute_name: "Please provide the name of the vendors and the services they will be providing.", attribute_type: "X", attribute_type_name: "Long Text", multi_val: nil, sort_order: 16, defn_state: 1 },
      { attribute_id: 23,     attribute_name: "What is the total estimated cost of all vendor-provided equipment and services (e.g, 99.50)?", attribute_type: "F", attribute_type_name: "Float", multi_val: nil, sort_order: 17, defn_state: 1 },
      { attribute_id: 35,     attribute_name: "Please select which vendors:",                                      attribute_type: "S", attribute_type_name: "String",        multi_val: "T", sort_order: 18, defn_state: 1 },
      { attribute_id: 24,     attribute_name: "What is your plan for inclement weather?",                          attribute_type: "S", attribute_type_name: "String",        multi_val: nil, sort_order: 19, defn_state: 1 },
      { attribute_id: 16,     attribute_name: "LS User",                                                           attribute_type: "X", attribute_type_name: "Long Text",     multi_val: nil, sort_order: 20, defn_state: 1 },
      { attribute_id: 15,     attribute_name: "LS Organization",                                                   attribute_type: "X", attribute_type_name: "Long Text",     multi_val: nil, sort_order: 21, defn_state: 1 },
      { attribute_id: 14,     attribute_name: "LS Event Name",                                                     attribute_type: "X", attribute_type_name: "Long Text",     multi_val: nil, sort_order: 22, defn_state: 1 },
      { attribute_id: 13,     attribute_name: "LS Event Description",                                              attribute_type: "X", attribute_type_name: "Long Text",     multi_val: nil, sort_order: 23, defn_state: 1 },
      { attribute_id: 12,     attribute_name: "LS Event Status",                                                   attribute_type: "X", attribute_type_name: "Long Text",     multi_val: nil, sort_order: 24, defn_state: 1 },
      { attribute_id: 11,     attribute_name: "LS Event Link",                                                     attribute_type: "X", attribute_type_name: "Long Text",     multi_val: nil, sort_order: 25, defn_state: 1 },
      { attribute_id: 10,     attribute_name: "LS Extra Information",                                              attribute_type: "X", attribute_type_name: "Long Text",     multi_val: nil, sort_order: 26, defn_state: 1 },
      { attribute_id: 9,      attribute_name: "LS Custom Questions",                                               attribute_type: "X", attribute_type_name: "Long Text",     multi_val: nil, sort_order: 27, defn_state: 1 },
      { attribute_id: -16,    attribute_name: "Allow Registration",                                                attribute_type: "B", attribute_type_name: "Boolean",       multi_val: nil, sort_order: 28, defn_state: 1 },
      { attribute_id: -21,    attribute_name: "Detail Image",                                                      attribute_type: "R", attribute_type_name: "File Reference", multi_val: nil, sort_order: 29, defn_state: 0 },
      { attribute_id: -20,    attribute_name: "Event Image",                                                      attribute_type: "R", attribute_type_name: "File Reference", multi_val: nil, sort_order: 30, defn_state: 1 },
      { attribute_id: -1,     attribute_name: "Web Site",                                                         attribute_type: "R", attribute_type_name: "File Reference", multi_val: nil, sort_order: 31, defn_state: 1 },
      { attribute_id: -50,    attribute_name: "SIS Term Code",                                                     attribute_type: "S", attribute_type_name: "String",        multi_val: nil, sort_order: 32, defn_state: 1 },
      { attribute_id: -51,    attribute_name: "SIS Subject Code",                                                  attribute_type: "S", attribute_type_name: "String",        multi_val: nil, sort_order: 33, defn_state: 1 },
      { attribute_id: -52,    attribute_name: "SIS Course Number",                                                 attribute_type: "S", attribute_type_name: "String",        multi_val: nil, sort_order: 34, defn_state: 1 },
      { attribute_id: -53,    attribute_name: "SIS Section Number",                                                attribute_type: "S", attribute_type_name: "String",        multi_val: nil, sort_order: 35, defn_state: 1 },
      { attribute_id: -54,    attribute_name: "SIS Level",                                                        attribute_type: "S", attribute_type_name: "String",        multi_val: nil, sort_order: 36, defn_state: 1 },
      { attribute_id: -55,    attribute_name: "SIS Credit Hours",                                                  attribute_type: "F", attribute_type_name: "Float",         multi_val: nil, sort_order: 37, defn_state: 1 },
      { attribute_id: -56,    attribute_name: "SIS Section Type",                                                  attribute_type: "S", attribute_type_name: "String",        multi_val: nil, sort_order: 38, defn_state: 1 },
      { attribute_id: -57,    attribute_name: "SIS Status Code",                                                   attribute_type: "S", attribute_type_name: "String",        multi_val: nil, sort_order: 39, defn_state: 1 },
      { attribute_id: -58,    attribute_name: "SIS Campus Code",                                                   attribute_type: "S", attribute_type_name: "String",        multi_val: nil, sort_order: 40, defn_state: 1 },
      { attribute_id: -59,    attribute_name: "SIS Sub-Term Code",                                                 attribute_type: "S", attribute_type_name: "String",        multi_val: nil, sort_order: 41, defn_state: 1 },
      { attribute_id: -61,    attribute_name: "SIS Institution Code",                                              attribute_type: "S", attribute_type_name: "String",        multi_val: nil, sort_order: 42, defn_state: 1 },
      { attribute_id: -62,    attribute_name: "SIS Instruction Method/Mode",                                       attribute_type: "S", attribute_type_name: "String",        multi_val: nil, sort_order: 43, defn_state: 1 },
      { attribute_id: -64,    attribute_name: "SIS Academic Department/Organization",                              attribute_type: "S", attribute_type_name: "String",        multi_val: nil, sort_order: 44, defn_state: 1 },
      { attribute_id: -65,    attribute_name: "SIS College/School/Group Code",                                     attribute_type: "S", attribute_type_name: "String",        multi_val: nil, sort_order: 45, defn_state: 1 },
      { attribute_id: -67,    attribute_name: "SIS Division Code",                                                 attribute_type: "S", attribute_type_name: "String",        multi_val: nil, sort_order: 46, defn_state: 1 },
      { attribute_id: -68,    attribute_name: "SIS Unique Section ID",                                             attribute_type: "S", attribute_type_name: "String",        multi_val: nil, sort_order: 47, defn_state: 1 },
      { attribute_id: -69,    attribute_name: "SIS Part of Day code",                                              attribute_type: "S", attribute_type_name: "String",        multi_val: nil, sort_order: 48, defn_state: 1 },
      { attribute_id: -70,    attribute_name: "SIS Crosslisted/Combined Indicator",                                attribute_type: "B", attribute_type_name: "Boolean",       multi_val: nil, sort_order: 49, defn_state: 1 },
      { attribute_id: -5,     attribute_name: "Conflict Decider",                                                  attribute_type: "S", attribute_type_name: "String",        multi_val: nil, sort_order: 50, defn_state: 0 },
      { attribute_id: -4,     attribute_name: "Hot Event Image",                                                   attribute_type: "R", attribute_type_name: "File Reference", multi_val: nil, sort_order: 51, defn_state: 0 },
      { attribute_id: -90,    attribute_name: "OutlookCalendarId",                                                 attribute_type: "S", attribute_type_name: "String",        multi_val: nil, sort_order: 52, defn_state: 0 },
      { attribute_id: -73,    attribute_name: "Priority Override",                                                 attribute_type: "B", attribute_type_name: "Boolean",       multi_val: nil, sort_order: 53, defn_state: 1 },
      { attribute_id: -2,     attribute_name: "Registration",                                                     attribute_type: "R", attribute_type_name: "File Reference", multi_val: nil, sort_order: 54, defn_state: 0 },
      { attribute_id: -71,    attribute_name: "SIS Bound Reservation Missing",                                     attribute_type: "B", attribute_type_name: "Boolean",       multi_val: nil, sort_order: 55, defn_state: 0 },
      { attribute_id: -80,    attribute_name: "WDYT Event Survey",                                                 attribute_type: "R", attribute_type_name: "File Reference", multi_val: nil, sort_order: 56, defn_state: 0 },
      { attribute_id: -13,    attribute_name: "X25 CIP Code",                                                     attribute_type: "S", attribute_type_name: "String",        multi_val: nil, sort_order: 57, defn_state: 0 },
      { attribute_id: -72,    attribute_name: "SIS Sync Paused",                                                   attribute_type: "B", attribute_type_name: "Boolean",       multi_val: "F", sort_order: 58, defn_state: 1 }
    ].freeze
  end
end

# frozen_string_literal: true

module TwentyFiveLive
  class EventCategory < ApplicationRecord
    self.table_name = "twenty_five_live_event_categories"

    include EncodedIds::HashidIdentifiable

    set_public_id_prefix :evc

    validates :twenty_five_live_id, presence: true, uniqueness: true
    validates :name, presence: true

    def active?
      defn_state == 1
    end

    def audience?
      name.start_with?("Audience -")
    end

    def calendar?
      name.start_with?("Calendar -")
    end

    def to_param
      public_id
    end

    EVENT_CATEGORIES = [
      { category_id: 124, category_name: "DTS Media - no show", sort_order: 1,  defn_state: 1 },
      { category_id: 122, category_name: "Final Review",         sort_order: 2,  defn_state: 1 },
      { category_id: 120, category_name: "CSV Import - SoM",     sort_order: 3,  defn_state: 1 },
      { category_id: 119, category_name: "CSV Import - SCDS",    sort_order: 4,  defn_state: 1 },
      { category_id: 118, category_name: "CSV Import - SoSH",    sort_order: 5,  defn_state: 1 },
      { category_id: 117, category_name: "CSV Import - SoE",     sort_order: 6,  defn_state: 1 },
      { category_id: 116, category_name: "CSV Import - SoAD",    sort_order: 7,  defn_state: 1 },
      { category_id: 115, category_name: "Finals Schedule",      sort_order: 8,  defn_state: 1 },
      { category_id: 103, category_name: "CSV - Staff",          sort_order: 9,  defn_state: 0 },
      { category_id: 102, category_name: "CSV - Enrollment",     sort_order: 10, defn_state: 0 },
      { category_id: 101, category_name: "CSV - Business",       sort_order: 11, defn_state: 0 },
      { category_id: 100, category_name: "CSV Import",           sort_order: 12, defn_state: 1 },
      { category_id: 56,  category_name: "Academic Related Event",                      sort_order: 13, defn_state: 1 },
      { category_id: 57,  category_name: "Audience - Alumni",                            sort_order: 14, defn_state: 1 },
      { category_id: 58,  category_name: "Athletics",                                     sort_order: 15, defn_state: 1 },
      { category_id: 59,  category_name: "Audience - Colleges of The Fenway (COF)",      sort_order: 16, defn_state: 1 },
      { category_id: 60,  category_name: "Audience - External Group",                    sort_order: 17, defn_state: 1 },
      { category_id: 61,  category_name: "Audience - Faculty",                           sort_order: 18, defn_state: 1 },
      { category_id: 62,  category_name: "Audience - Prospective Students / Families",   sort_order: 19, defn_state: 1 },
      { category_id: 63,  category_name: "Audience - Staff",                             sort_order: 20, defn_state: 1 },
      { category_id: 64,  category_name: "Audience - Students",                          sort_order: 21, defn_state: 1 },
      { category_id: 105, category_name: "Academic Calendar",                            sort_order: 22, defn_state: 1 },
      { category_id: 106, category_name: "Calendar - Admissions Undergraduate",          sort_order: 23, defn_state: 1 },
      { category_id: 107, category_name: "Calendar - Admissions Graduate",               sort_order: 24, defn_state: 1 },
      { category_id: 108, category_name: "Calendar - Admissions International",          sort_order: 25, defn_state: 1 },
      { category_id: 110, category_name: "Calendar - Alumni",                            sort_order: 26, defn_state: 1 },
      { category_id: 111, category_name: "Calendar - Athletics",                         sort_order: 27, defn_state: 1 },
      { category_id: 104, category_name: "Calendar - Main",                              sort_order: 28, defn_state: 1 },
      { category_id: 109, category_name: "Calendar - Student Life",                      sort_order: 29, defn_state: 1 },
      { category_id: 65,  category_name: "Community Event",                              sort_order: 30, defn_state: 1 },
      { category_id: 66,  category_name: "Cultural Event",                               sort_order: 31, defn_state: 1 },
      { category_id: 67,  category_name: "Do Not Display Event on Published Calendars",  sort_order: 32, defn_state: 1 },
      { category_id: 68,  category_name: "Donor Event",                                  sort_order: 33, defn_state: 1 },
      { category_id: 69,  category_name: "Industry Partnership",                         sort_order: 34, defn_state: 1 },
      { category_id: 70,  category_name: "Marquee Partnership",                          sort_order: 35, defn_state: 1 },
      { category_id: 71,  category_name: "Audience - Open to the Public",                sort_order: 36, defn_state: 1 },
      { category_id: -1,  category_name: "Publish to vCalendar",                         sort_order: 37, defn_state: 0 },
      { category_id: -2,  category_name: "Featured Event",                               sort_order: 38, defn_state: 0 }
    ].freeze
  end
end

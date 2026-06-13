# frozen_string_literal: true

module TwentyFiveLive
  class OrganizationCategory
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

    ORGANIZATION_CATEGORIES = [
      { category_id: 36, category_name: "Academic Affairs",                                          sort_order: 1,  defn_state: 1 },
      { category_id: 37, category_name: "Business Division",                                          sort_order: 2,  defn_state: 1 },
      { category_id: 38, category_name: "Colleges of The Fenway (COF)",                               sort_order: 3,  defn_state: 1 },
      { category_id: 39, category_name: "Inclusive Excellence",                                       sort_order: 4,  defn_state: 1 },
      { category_id: 40, category_name: "Enrollment Management",                                      sort_order: 5,  defn_state: 1 },
      { category_id: 41, category_name: "Institutional Advancement and External Relations (IAER)",    sort_order: 6,  defn_state: 1 },
      { category_id: 42, category_name: "K-12 School - Private",                                      sort_order: 7,  defn_state: 1 },
      { category_id: 43, category_name: "K-12 School - Public",                                       sort_order: 8,  defn_state: 1 },
      { category_id: 92, category_name: "Professional and Continuing Studies",                         sort_order: 9,  defn_state: 1 },
      { category_id: 44, category_name: "ROTC",                                                       sort_order: 10, defn_state: 1 },
      { category_id: 45, category_name: "School of Architecture and Design (SOAD)",                   sort_order: 11, defn_state: 1 },
      { category_id: 46, category_name: "School of Computing and Data Science (SCDS)",                sort_order: 12, defn_state: 1 },
      { category_id: 47, category_name: "School of Engineering (SOE)",                                sort_order: 13, defn_state: 1 },
      { category_id: 48, category_name: "School of Management (SOM)",                                 sort_order: 14, defn_state: 1 },
      { category_id: 49, category_name: "School of Science and Humanities (SOSH)",                    sort_order: 15, defn_state: 1 },
      { category_id: 50, category_name: "Student Affairs",                                            sort_order: 16, defn_state: 1 },
      { category_id: 98, category_name: "Student Club - CDGE",                                        sort_order: 17, defn_state: 1 },
      { category_id: 97, category_name: "Student Club - CSL",                                         sort_order: 18, defn_state: 1 },
      { category_id: 52, category_name: "Student Club Sports",                                        sort_order: 19, defn_state: 1 },
      { category_id: 53, category_name: "Student Organization",                                       sort_order: 20, defn_state: 1 },
      { category_id: 54, category_name: "Study Abroad",                                               sort_order: 21, defn_state: 1 },
      { category_id: 55, category_name: "Transformational Learning and Partnership (TLP)",             sort_order: 22, defn_state: 1 },
      { category_id: 93, category_name: "WIT Graduate",                                               sort_order: 23, defn_state: 1 },
      { category_id: 94, category_name: "WIT Undergraduate Day",                                      sort_order: 24, defn_state: 1 },
    ].freeze

    def self.find_by_id(id)
      raw = ORGANIZATION_CATEGORIES.find { |c| c[:category_id] == id }
      return nil unless raw

      new(id: raw[:category_id], name: raw[:category_name],
          sort_order: raw[:sort_order], defn_state: raw[:defn_state])
    end

    def self.all
      ORGANIZATION_CATEGORIES.map do |c|
        new(id: c[:category_id], name: c[:category_name],
            sort_order: c[:sort_order], defn_state: c[:defn_state])
      end
    end
  end
end

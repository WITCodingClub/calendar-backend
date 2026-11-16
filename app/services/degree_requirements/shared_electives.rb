# frozen_string_literal: true

module DegreeRequirements
  # Links the elective slots whose list is not on the program page. Most
  # open slots in a plan are of this kind: "HSS Elective", "English
  # Sequence", "Free Elective", "Co-op Semester". The catalog defines them
  # once for every program, on its policy pages:
  #
  # - Humanities & Social Science Requirement
  #   (/academic-policies-procedures/ug/hss-elective-requirements/): the
  #   humanities and social science subjects.
  # - English Placement (/academic-policies-procedures/ug/english-placement/):
  #   the English sequences.
  #
  # Each list (SharedElectiveList) becomes an ElectiveGroup of the set with no
  # plan: a list of courses, a list of subjects (subject_codes), or any
  # course (any_course).
  # A slot that the program page already linked keeps its list. A slot that
  # no rule names, such as "CONM Elective", stays open.
  #
  # PlanWriter runs it after each import. `bin/rails
  # degree_requirements:shared_electives` runs it on every stored set.
  class SharedElectives
    HSS_URL = "#{SITE_URL}/academic-policies-procedures/ug/hss-elective-requirements/".freeze
    ENGLISH_URL = "#{SITE_URL}/academic-policies-procedures/ug/english-placement/".freeze

    # The notes each list gets, by kind.
    NOTES = {
      hss:            "Any humanities or social science course (#{HSS_URL})",
      humanities:     "Any humanities course (#{HSS_URL})",
      social_science: "Any social science course (#{HSS_URL})",
      english:        "The English sequence from the English placement (#{ENGLISH_URL})",
      co_op:          "COOP3500 and COOP4500 are required. COOP5000 is an additional co-op work semester.",
      free:           "Any course",
      directed_hss:   "A directed HSS elective (#{HSS_URL})"
    }.freeze

    # "HSS 03 Elective (PSYC4552)": a directed HSS elective names its course.
    DIRECTED = /\A(?:hss|hhs)\b[^()]*\(\s*([a-z]{4})\s*(\d{3,4})\s*\)\z/i
    # A bare "Elective" is left out: on some pages it means a program elective.
    FREE_LABEL = /\A(?:free|general|open)\s+electives?\z/

    def self.call(set) = new(set).call

    # The SharedElectiveList for a slot label, or nil. Only a label that
    # names the whole requirement matches: "Math or Science Elective" names
    # no list.
    def self.rule_for(label)
      text = label.to_s.downcase.gsub(/[*†]/, "").squish
      if (match = DIRECTED.match(text))
        return SharedElectiveList.directed([ match[1].upcase, match[2].to_i ], label.to_s.squish)
      end

      bare = text.sub(/[\s\d]+\z/, "")
      case bare
      when /\Aenglish sequence\z/ then SharedElectiveList::ENGLISH
      when /\A(?:hss|hhs)(?:\s+\d{1,2})?\s+electives?\z/, %r{\Ahumanities\s*(?:or|and|&|/)\s*social sciences?\s+electives?\z}
        SharedElectiveList::HSS
      when /\Ahumanities\s+electives?\z/ then SharedElectiveList::HUMANITIES_LIST
      when /\Asocial sciences?\s+electives?\z/ then SharedElectiveList::SOCIAL_SCIENCES_LIST
      when /\Aco-?op(?:\s+semester)?\z/ then SharedElectiveList::CO_OP
      when FREE_LABEL then SharedElectiveList::FREE
      end
    end

    def initialize(set)
      @set = set
    end

    # Links each open slot that a rule names. Returns the number of slots
    # linked.
    def call
      items = ProgramPlanItem.joins(:program_plan)
                             .where(program_plans: { requirement_set_id: @set.id }, kind: "placeholder", elective_group_id: nil)
      linked = 0

      ElectiveGroup.transaction do
        # One run at a time for a set: each new list takes the next position.
        RequirementSet.where(id: @set.id).lock.pluck(:id)
        items.find_each do |item|
          rule = self.class.rule_for(item.label)
          next if rule.nil?

          item.update_columns(elective_group_id: group_for(rule).id, updated_at: Time.current)
          linked += 1
        end
      end
      linked
    end

    private

    # One list for each rule in a set, made the first time a slot needs it.
    def group_for(rule)
      @groups ||= {}
      @groups[rule.name] ||= @set.elective_groups.find_by(program_plan_id: nil, name: rule.name) || create_group(rule)
    end

    def create_group(rule)
      position = (@set.elective_groups.maximum(:position) || -1) + 1
      group = @set.elective_groups.create!(name: rule.name, heading: rule.heading, notes: NOTES.fetch(rule.kind), position: position,
                                           subject_codes: rule.subject_codes, any_course: rule.any_course)
      rule.courses.each_with_index do |(subject, number), index|
        group.courses.create!(subject_code: subject, course_number: number, position: index)
      end
      group
    end
  end
end

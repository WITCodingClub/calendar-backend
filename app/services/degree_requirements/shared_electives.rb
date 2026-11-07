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
  # Each rule becomes an ElectiveGroup of the set with no plan: a list of
  # courses, a list of subjects (subject_codes), or any course (any_course).
  # A slot that the program page already linked keeps its list. A slot that
  # no rule names, such as "CONM Elective", stays open.
  #
  # PlanWriter runs it after each import. `bin/rails
  # degree_requirements:shared_electives` runs it on every stored set.
  class SharedElectives
    HSS_URL = "#{SITE_URL}/academic-policies-procedures/ug/hss-elective-requirements/".freeze
    ENGLISH_URL = "#{SITE_URL}/academic-policies-procedures/ug/english-placement/".freeze

    HUMANITIES = %w[CSAS HIST HSSI HUMN LITR PHIL].freeze
    SOCIAL_SCIENCES = %w[COMM CSAS ECON ENVM HSSI POLS PSYC SOCL].freeze
    # Every course of the four English sequences. A slot takes one course.
    ENGLISH_SEQUENCE = [ [ "ENGL", 700 ], [ "ENGL", 800 ], [ "ENGL", 900 ], [ "ENGL", 1100 ], [ "ENGL", 2200 ] ].freeze

    Rule = Data.define(:name, :heading, :notes, :subject_codes, :courses, :any_course)

    HSS = Rule.new(name: "HSS Electives", heading: "Humanities or social science elective",
                   notes: "Any humanities or social science course (#{HSS_URL})",
                   subject_codes: (HUMANITIES + SOCIAL_SCIENCES).uniq.sort, courses: [], any_course: false)
    HUMANITIES_RULE = Rule.new(name: "Humanities Electives", heading: "Humanities elective",
                               notes: "Any humanities course (#{HSS_URL})",
                               subject_codes: HUMANITIES, courses: [], any_course: false)
    SOCIAL_SCIENCES_RULE = Rule.new(name: "Social Science Electives", heading: "Social science elective",
                                    notes: "Any social science course (#{HSS_URL})",
                                    subject_codes: SOCIAL_SCIENCES, courses: [], any_course: false)
    ENGLISH = Rule.new(name: "English Sequence", heading: "One course of the student's English sequence",
                       notes: "The English sequence from the English placement (#{ENGLISH_URL})",
                       subject_codes: [], courses: ENGLISH_SEQUENCE, any_course: false)
    # A co-op semester is a work term. COOP2500 (Introduction to Cooperative
    # Education) is a course row of its own, required before the first
    # term, so it does not meet a co-op semester. Nor does COOP3000
    # (optional co-op) or COOP6500 (graduate).
    CO_OP_TERMS = [ [ "COOP", 3500 ], [ "COOP", 4500 ], [ "COOP", 5000 ] ].freeze
    CO_OP = Rule.new(name: "Co-op", heading: "Co-op semester",
                     notes: "COOP3500 and COOP4500 are required. COOP5000 is an additional co-op work semester.",
                     subject_codes: [], courses: CO_OP_TERMS, any_course: false)
    FREE = Rule.new(name: "Free Electives", heading: "Free or general elective", notes: "Any course",
                    subject_codes: [], courses: [], any_course: true)

    # "HSS 03 Elective (PSYC4552)": a directed HSS elective names its course.
    DIRECTED = /\A(?:hss|hhs)\b[^()]*\(\s*([a-z]{4})\s*(\d{3,4})\s*\)\z/i
    # A bare "Elective" is left out: on some pages it means a program elective.
    FREE_LABEL = /\A(?:free|general|open)\s+electives?\z/

    def self.call(set) = new(set).call

    # The rule for a slot label, or nil. Only a label that names the whole
    # requirement matches: "Math or Science Elective" names no rule.
    def self.rule_for(label)
      text = label.to_s.downcase.gsub(/[*†]/, "").squish
      if (match = DIRECTED.match(text))
        code = [ match[1].upcase, match[2].to_i ]
        return Rule.new(name: "HSS Elective (#{code.join})", heading: label.to_s.squish,
                        notes: "A directed HSS elective (#{HSS_URL})", subject_codes: [], courses: [ code ], any_course: false)
      end

      bare = text.sub(/[\s\d]+\z/, "")
      case bare
      when /\Aenglish sequence\z/ then ENGLISH
      when /\A(?:hss|hhs)(?:\s+\d{1,2})?\s+electives?\z/, %r{\Ahumanities\s*(?:or|and|&|/)\s*social sciences?\s+electives?\z}
        HSS
      when /\Ahumanities\s+electives?\z/ then HUMANITIES_RULE
      when /\Asocial sciences?\s+electives?\z/ then SOCIAL_SCIENCES_RULE
      when /\Aco-?op(?:\s+semester)?\z/ then CO_OP
      when FREE_LABEL then FREE
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
      group = @set.elective_groups.create!(name: rule.name, heading: rule.heading, notes: rule.notes, position: position,
                                           subject_codes: rule.subject_codes, any_course: rule.any_course)
      rule.courses.each_with_index do |(subject, number), index|
        group.courses.create!(subject_code: subject, course_number: number, position: index)
      end
      group
    end
  end
end

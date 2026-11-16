# frozen_string_literal: true

module AcademicProfiles
  # Which course the student took fills which requirement of one program.
  # Each course counts toward one requirement only. Required courses take a
  # course first, then choices, then elective slots, so an elective slot does
  # not use a course a required row needs. DegreeProgress builds the JSON of
  # the rows from the result.
  #
  # pool: the best attempts of the student (CourseHistory#attempts).
  class RequirementFill
    # courses: the course of each plan item id, or nil. needs: the HSS
    # category that a generic HSS slot stands for, by item id. hss: what
    # counts toward the HSS requirement, or nil; english and hss_slots: the
    # courses in the English and the HSS slots (all three for HssDetails).
    # counted: the courses that fill a row.
    Plan = Data.define(:courses, :needs, :hss, :english, :hss_slots, :counted)
    # courses is nil for a list that cannot be checked.
    List = Data.define(:group, :courses, :needed)

    def initialize(pool, course_keys:, credits:, hss_matcher:)
      @pool = pool
      @course_keys = course_keys
      @credits = credits
      @hss_matcher = hss_matcher
    end

    # The rows of a plan of study. A slot with a list of courses goes first,
    # then a slot with a list of subjects (an HSS elective), then a free
    # elective. A broad slot then does not use a course that a narrow one
    # needs.
    def plan(set, plan)
      groups = set.elective_groups.index_by(&:id)
      items = plan.items.to_a
      results = {}
      needs = {}
      used = []

      items.select(&:course?).each { |item| results[item.id] = take(used, [ item.key ]) }
      items.select(&:choice?).each do |item|
        results[item.id] = take(used, item.options.map { |option| CourseCode.key_of(option) })
      end
      slots = items.select(&:placeholder?).filter_map { |item| [ item, groups[item.elective_group_id] ] if item.elective_group_id }
      hss_slots, slots = slots.partition { |_, group| group.shared_kind == :hss }
      narrow, broad = slots.partition { |_, group| !group.any_course }
      narrow.sort_by.with_index { |(_, group), index| [ breadth(group), width(group), index ] }.each do |item, group|
        results[item.id] = take_for(used, group)
      end
      hss = hss_progress(set, items, groups, results, used)
      assign_hss(hss, hss_slots, results, needs, used)
      broad.each { |item, group| results[item.id] = take_for(used, group) }

      Plan.new(courses: results, needs: needs, hss: hss,
               english: english_items(items, groups).filter_map { |item| results[item.id] },
               hss_slots: hss_courses(items, groups, results), counted: results.values.compact.uniq)
    end

    # A program with no plan of study, such as a minor: each elective list
    # with the courses that count toward its minimum. Returns the lists and
    # the courses they count.
    def lists(set)
      used = []
      lists = set.elective_groups.map do |group|
        next List.new(group: group, courses: nil, needed: nil) unless countable?(group)

        codes = group.courses.map(&:key)
        needed = group.min_courses || (group.min_credits ? nil : codes.size)
        courses = []
        while (course = take(used, codes))
          courses << course
          break if needed && courses.size >= needed
          break if needed.nil? && @credits.sum(courses) >= group.min_credits
        end
        List.new(group: group, courses: courses, needed: needed)
      end
      [ lists, used ]
    end

    def list_rule(group)
      @list_rules ||= {}
      @list_rules[group.id] ||= ElectiveListRule.new(group, @course_keys)
    end

    private

    # What counts toward the HSS requirement before the "HSS Elective" slots
    # take a course: the courses in the other HSS slots (Humanities Elective,
    # a directed course), the required course rows in an HSS category
    # (ECON4102 in Construction Management, PHIL4525 in Applied AI), and a
    # third English course, which the notes let count as Humanities. nil for
    # a program with no HSS requirement and no HSS slot.
    def hss_progress(set, items, groups, results, used)
      slots = items.any? { |item| groups[item.elective_group_id]&.hss_list? }
      return nil if set.hss_requirement.blank? && !slots

      categories = HssMatcher.categories(set)
      rows = items.reject(&:placeholder?).filter_map { |item| results[item.id] }
                  .select { |course| categories.any? { |category| @hss_matcher.in_category?(category, course) } }
      english = take_where(used) { |candidate| english_sequence?(candidate) } if english_slots_full?(items, groups, results)
      { categories: categories, min_credits: set.hss_requirement&.dig("min_credits"), english_humanities: english,
        met: hss_courses(items, groups, results) + rows + [ english ].compact, rows: rows }
    end

    def english_sequence?(course)
      SharedElectiveList::ENGLISH_SEQUENCE.any? { |code| @course_keys.same?(code, course.key) }
    end

    def english_slots_full?(items, groups, results)
      slots = english_items(items, groups)
      slots.any? && slots.all? { |item| results[item.id] }
    end

    # The HSS slots of a plan, such as "HSS Elective", take courses so that
    # the major's categories are met: one humanities course, one social
    # science course, an Ethics course, ... (RequirementSet#hss_requirement).
    # A course in another HSS slot (Humanities Elective, a directed course)
    # already counts. Each slot takes a course for the first category that
    # no course meets yet, or stays open for it, and names it in needs.
    # With every category met, a slot takes any HSS course.
    def assign_hss(hss, slots, results, needs, used)
      return if slots.empty? || hss.nil?

      met = hss[:met].dup
      categories = hss[:categories].select { |category| HssMatcher.checkable?(category) }
      slots.each do |item, group|
        category = categories.find do |candidate|
          met.none? { |course| @hss_matcher.in_category?(candidate, course, english_humanities: hss[:english_humanities]) } &&
            needs.values.exclude?(candidate["name"])
        end
        if category
          needs[item.id] = category["name"]
          course = take_where(used) { |candidate| @hss_matcher.in_category?(category, candidate) }
        else
          course = take_for(used, group)
        end
        results[item.id] = course
        met << course if course
      end
    end

    def hss_courses(items, groups, results)
      items.select { |item| item.placeholder? && groups[item.elective_group_id]&.hss_list? }.filter_map { |item| results[item.id] }
    end

    def english_items(items, groups) = items.select { |item| groups[item.elective_group_id]&.shared_kind == :english }

    def breadth(group)
      return 2 if group.any_course
      return 1 if group.subject_codes.any?

      0
    end

    # Among lists of one kind, the shorter list first: "Humanities" before
    # "HSS".
    def width(group) = group.subject_codes.any? ? group.subject_codes.size : group.courses.size

    # A list with no minimum that is not a "Required ..." list cannot be
    # checked.
    def countable?(group)
      group.min_courses || group.min_credits || group.every_course_required?
    end

    # The best unused course that meets an elective list (ElectiveListRule).
    def take_for(used, group)
      rule = list_rule(group)
      take_where(used) { |candidate| rule.accepts?(candidate.key) }
    end

    # The best unused course that meets one of the codes.
    def take(used, codes)
      keys = @course_keys.expand(codes)
      take_where(used) { |candidate| keys.include?(candidate.key) }
    end

    # A done course before one in progress. Marks it used.
    def take_where(used)
      course = @pool.reject { |candidate| used.include?(candidate) }
                    .select { |candidate| yield candidate }
                    .min_by { |candidate| CourseHistory::RANK.fetch(candidate.status) }
      used << course if course
      course
    end
  end
end

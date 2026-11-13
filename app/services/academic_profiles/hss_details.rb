# frozen_string_literal: true

module AcademicProfiles
  # The `hss` entry of a program of DegreeProgress (#799, #991): the
  # categories of the major with their status, course, and hint, the English
  # sequence courses, each course that counts toward HSS with its category,
  # and the credits against the minimum.
  #
  # The open HSS slots of the plan need the planned terms of the rows, which
  # PlanTerms adds after this entry is built. DegreeProgress calls
  # HssDetails.with_open_slots on the program entry with the terms.
  class HssDetails
    # hss: the HSS progress of DegreeProgress#hss_progress (categories,
    # min_credits, english_humanities, rows). english: the courses in the
    # English Sequence slots. slot_courses: the courses in the HSS slots.
    # matcher: an HssMatcher.
    def initialize(hss, english:, slot_courses:, matcher:)
      @hss = hss
      @english = english
      @matcher = matcher
      @courses = (slot_courses + hss[:rows] + [ hss[:english_humanities] ].compact).uniq
    end

    # credits is english.credits plus the credits of each course: a course
    # counts in one of them only.
    def call
      english = @english.uniq - @courses
      {
        min_credits: @hss[:min_credits],
        credits:     credits(english) + credits(@courses),
        categories:  @hss[:categories].map { |category| category_json(category) },
        english:     { credits: credits(english), courses: english.map(&:code) },
        courses:     @courses.map { |course| course_json(course) }
      }
    end

    # The program entry with hss.open_slots: each open row of an HSS slot,
    # with its planned term and the category it waits for. The planned terms
    # are null without a start term.
    def self.with_open_slots(entry)
      return entry if entry[:hss].nil?

      slots = entry[:requirements].select { |row| row[:status] == "open" && HssMatcher.slot_list?(row[:elective_list]) }
      entry.merge(hss: entry[:hss].merge(open_slots: slots.map { |row| row.slice(:label, :planned_term, :planned_term_uid, :hss_category) }))
    end

    private

    def credits(courses) = courses.sum { |course| course.credits.to_i }

    def category_json(category)
      checkable = HssMatcher.checkable?(category)
      course = checkable && @courses.select { |candidate| meets?(category, candidate) }.min_by { |c| DegreeProgress::RANK.fetch(c.status) }
      { name: category["name"], checkable: checkable, status: course ? course.status : "open", course: course ? course.code : nil,
        hint: HssMatcher.hint(category) }
    end

    # category: the first category, in category order, that the course meets,
    # or nil (a course in a Humanities slot can have a subject of no category).
    def course_json(course)
      { code: course.code, title: course.title, credits: course.credits, status: course.status,
        category: @matcher.category_of(@hss[:categories], course, english_humanities: @hss[:english_humanities]) }
    end

    def meets?(category, course) = @matcher.in_category?(category, course, english_humanities: @hss[:english_humanities])
  end
end

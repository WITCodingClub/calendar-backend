# frozen_string_literal: true

module Catalog
  # One elective list PDF of a term (TermElectiveList) as the public catalog
  # API and the MCP tools return it. courses are the rows the query kept.
  # text is the full text of the PDF: it has the rules that name no course,
  # such as "Any 2000-Level courses in BIOE, BIOL, ...".
  class TermElectiveListSerializer
    def initialize(list, courses: list.courses)
      @list = list
      @courses = courses
    end

    def as_json(*)
      {
        school:     @list.school,
        title:      @list.title,
        url:        @list.url,
        fetched_at: @list.fetched_at.iso8601,
        courses:    @courses.map { |course| course_json(course) },
        text:       @list.body_text
      }
    end

    private

    def course_json(course)
      {
        code:    course.code,
        title:   course.catalog_course&.title,
        heading: course.heading
      }
    end
  end
end

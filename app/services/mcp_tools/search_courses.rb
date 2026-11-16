# frozen_string_literal: true

module McpTools
  class SearchCourses < BaseTool
    tool_name "search_courses"
    title "Search courses"
    description "Searches Wentworth courses (not sections) by code or title words, for example \"COMP 2350\" or " \
                "\"network security\". Filter by subject code, or by a term to list only the courses offered in it. " \
                "Call get_course for prerequisites and the full description."
    requires_scope "catalog"
    academic_planning :course_details
    input_schema(
      properties: {
        q:        { type: "string", description: "A course code, or words in the title." },
        subject:  { type: "array", items: { type: "string" }, description: "Subject codes, for example COMP or MATH." },
        term_uid: { type: "integer", description: "Only courses with a section in this term." },
        page:     PAGE_SCHEMA,
        per_page: per_page_schema(:courses)
      }
    )
    output_schema(Schemas.object(courses: Schemas.array(Schemas::COURSE_SUMMARY), meta: Schemas::PAGE_META))

    def perform(q: nil, subject: nil, term_uid: nil, page: nil, per_page: nil)
      page     = Catalog::Page.new(:courses, page: page, per_page: per_page)
      relation = Catalog::CourseQuery.new.call(q: q, subject: subject, term_uid: term_uid)

      {
        courses: page.of(relation).map { |course| Catalog::CourseSerializer.summary(course) },
        meta:    page.meta(relation.count)
      }
    end
  end
end

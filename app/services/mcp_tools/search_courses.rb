# frozen_string_literal: true

module McpTools
  # GET /api/v1/catalog/courses. GraphQL: courses.
  class SearchCourses < BaseTool
    DEFAULT_PER_PAGE = 25
    MAX_PER_PAGE     = Catalog::CourseQuery::MAX_PER_PAGE

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
        per_page: { type: "integer", minimum: 1, maximum: MAX_PER_PAGE, description: "Default #{DEFAULT_PER_PAGE}." }
      }
    )

    def perform(q: nil, subject: nil, term_uid: nil, page: nil, per_page: nil)
      page, per_page = page_params(page, per_page, default: DEFAULT_PER_PAGE, max: MAX_PER_PAGE)
      relation = Catalog::CourseQuery.new.call(q: q, subject: subject, term_uid: term_uid)
      total    = relation.count

      {
        courses: relation.page(page).per(per_page).map { |course| Catalog::CourseSerializer.summary(course) },
        meta:    page_meta(page, per_page, total)
      }
    end
  end
end

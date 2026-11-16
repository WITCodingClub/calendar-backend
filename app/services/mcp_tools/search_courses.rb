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
      properties: CatalogFilters.properties(Catalog::CourseQuery).merge(page: PAGE_SCHEMA, per_page: per_page_schema(:courses))
    )
    output_schema(Schemas.object(courses: Schemas.array(Schemas::COURSE_SUMMARY), meta: Schemas::PAGE_META))

    def perform(page: nil, per_page: nil, **arguments)
      list = Catalog::ListRequest.new(:courses, CatalogFilters.filters(Catalog::CourseQuery, arguments),
                                      page: page, per_page: per_page, surface: :mcp)

      { courses: list.rows, meta: list.meta }
    end
  end
end

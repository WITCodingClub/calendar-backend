# frozen_string_literal: true

module McpTools
  # The catalog MCP App: section cards (search_sections, similar_sections,
  # get_section), a course with its prerequisite tree (get_course), and an
  # instructor with the ratings and reviews (get_instructor).
  class CatalogApp < AppResource
    uri "ui://wit-calendar/catalog"
    resource_name "catalog"
    title "Catalog"
    description "Course sections, a course, or an instructor from the catalog."
    mime_type MCP::Apps::RESOURCE_MIME_TYPE
    template "catalog.html"
  end
end

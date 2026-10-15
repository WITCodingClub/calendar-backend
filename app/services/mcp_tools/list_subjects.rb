# frozen_string_literal: true

module McpTools
  # GET /api/v1/catalog/subjects. GraphQL: subjects.
  class ListSubjects < BaseTool
    tool_name "list_subjects"
    title "List subjects"
    description "Lists the subjects that have sections, with the short code that search_sections takes " \
                "(for example COMP) and the section count."
    requires_scope "catalog"
    input_schema(properties: { term_uid: { type: "integer", description: "Only subjects with sections in this term." } })

    def perform(term_uid: nil)
      { term_uid: term_uid, subjects: Catalog::SubjectQuery.new.call(term_uid: term_uid) }.compact
    end
  end
end

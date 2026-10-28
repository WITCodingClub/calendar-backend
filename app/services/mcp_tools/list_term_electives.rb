# frozen_string_literal: true

module McpTools
  # GET /api/v1/catalog/terms/:uid/electives. The class is not named
  # TermElectives, because that module holds the import.
  class ListTermElectives < BaseTool
    tool_name "list_term_electives"
    title "List term electives"
    description "Lists the elective lists that each Wentworth school publishes for one term, such as the " \
                "Computer Science Electives or the HSS electives offered that term. Each list gives the " \
                "courses with the heading they are under, and the full text of the PDF, which has the rules " \
                "that name no course, such as \"Any 2000-Level courses in ...\". The headings come from the " \
                "PDF layout, so read the text when a heading is not clear. A school that has not sent its " \
                "list has none; the student asks the dean or associate dean of that school."
    requires_scope "catalog"
    academic_planning :term_electives
    input_schema(
      properties: {
        term_uid: TERM_SCHEMA,
        school:   { type: "string", enum: TermElectives::SCHOOLS, description: "Only the lists of this school." },
        course:   { type: "string", description: "Only this course, for example COMP2000, to see which lists " \
                                                 "name it." },
        q:        { type: "string", description: "Words in the heading, for example computer science." }
      }
    )
    output_schema(
      Schemas.object(
        term:  Schemas::TERM_REF,
        lists: Schemas.array(Schemas::TERM_ELECTIVE_LIST)
      )
    )

    def perform(term_uid: nil, school: nil, course: nil, q: nil)
      term = find_term(term_uid)
      matches = Catalog::TermElectiveQuery.new.call(term: term, school: school, course: course, q: q)

      { term:  { uid: term.uid, name: term.name },
        lists: matches.map { |match| Catalog::TermElectiveListSerializer.new(match.list, courses: match.courses).as_json } }
    rescue Catalog::FilterError => e
      raise ToolError, e.message
    end
  end
end

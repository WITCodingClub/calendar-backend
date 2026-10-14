# frozen_string_literal: true

module McpTools
  # GET /api/v1/catalog/terms, /terms/current, /terms/next. GraphQL: terms.
  class ListTerms < BaseTool
    tool_name "list_terms"
    title "List terms"
    description "Lists the Wentworth academic terms, newest first, with the uid that the other tools take. " \
                "current_term_uid is the term in session today, and next_term_uid is the one after it."
    input_schema(
      properties: { active: { type: "boolean", description: "Only the terms in session today." } }
    )

    def perform(active: false)
      counts = Course.active.group(:term_id).count
      terms  = (active ? Term.active : Term.reverse_chronological).to_a

      {
        current_term_uid: Term.current&.uid,
        next_term_uid:    Term.next_uid,
        terms:            terms.map { |term| Catalog::TermSerializer.new(term, section_count: counts.fetch(term.id, 0)).as_json }
      }
    end
  end
end

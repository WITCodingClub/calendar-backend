# frozen_string_literal: true

module McpTools
  class ListTerms < BaseTool
    tool_name "list_terms"
    title "List terms"
    description "Lists the Wentworth academic terms, newest first, with the uid that the other tools take. " \
                "current_term_uid is the term in session today, and next_term_uid is the one after it."
    requires_scope "catalog"
    input_schema(
      properties: { active: { type: "boolean", description: "Only the terms in session today." } }
    )
    output_schema(
      Schemas.object(
        current_term_uid: Schemas.nullable(Schemas::INTEGER),
        next_term_uid:    Schemas.nullable(Schemas::INTEGER),
        terms:            Schemas.array(Schemas::TERM)
      )
    )

    def perform(active: false)
      terms = active ? Term.active : Term.reverse_chronological

      {
        current_term_uid: Term.current&.uid,
        next_term_uid:    Term.next_uid,
        terms:            Catalog::TermSerializer.collection(terms)
      }
    end
  end
end

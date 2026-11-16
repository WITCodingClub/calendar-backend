# frozen_string_literal: true

module Api
  module V1
    module Catalog
      # The elective lists that each school publishes for the term
      # (docs/term-electives.md).
      class TermElectivesController < Api::V1::PublicController
        def index
          term = Term.find_by_uid!(params[:uid])

          matches = ::Catalog::TermElectiveQuery.new.call(term: term, **filter_params(::Catalog::TermElectiveQuery))

          render_collection(
            matches.map { |match| ::Catalog::TermElectiveListSerializer.new(match.list, courses: match.courses).as_json },
            meta: { count: matches.size, term_uid: term.uid, term: term.name }
          )
        end
      end
    end
  end
end

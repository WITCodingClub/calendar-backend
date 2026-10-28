# frozen_string_literal: true

module Api
  module V1
    module Catalog
      # GET /api/v1/catalog/terms/:uid/electives
      #
      # The elective lists that each school publishes for the term
      # (docs/term-electives.md).
      class TermElectivesController < Api::V1::PublicController
        def index
          term = Term.find_by(uid: params[:uid])
          raise ActiveRecord::RecordNotFound, "No term #{params[:uid]}" if term.nil?

          matches = ::Catalog::TermElectiveQuery.new.call(
            term: term, school: array_param(:school), course: params[:course], q: params[:q]
          )

          render_collection(
            matches.map { |match| ::Catalog::TermElectiveListSerializer.new(match.list, courses: match.courses).as_json },
            meta: { count: matches.size, term_uid: term.uid, term: term.name }
          )
        end
      end
    end
  end
end

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
            term: term, school: array_param(:school), course: string_param(:course), q: string_param(:q)
          )

          render_collection(
            matches.map { |match| ::Catalog::TermElectiveListSerializer.new(match.list, courses: match.courses).as_json },
            meta: { count: matches.size, term_uid: term.uid, term: term.name }
          )
        end

        private

        # ?q[]=x would give the words of the array's text, and the edge cache
        # would keep the wrong answer for an hour.
        def string_param(key)
          value = params[key]
          return value if value.nil? || value.is_a?(String)

          raise ::Catalog::FilterError, "#{key} must be one value"
        end
      end
    end
  end
end

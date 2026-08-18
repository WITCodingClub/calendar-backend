# frozen_string_literal: true

module Api
  module V1
    module Catalog
      # GET /api/v1/catalog/terms
      class TermsController < Api::V1::PublicController
        def index
          terms  = Term.reverse_chronological.to_a
          counts = Course.active.group(:term_id).count

          render_collection(
            terms.map { |term| ::Catalog::TermSerializer.new(term, section_count: counts.fetch(term.id, 0)).as_json },
            meta: { count: terms.size }
          )
        end

        def show
          term  = Term.find_by!(uid: params[:uid])
          count = Course.active.where(term_id: term.id).count

          render_resource(::Catalog::TermSerializer.new(term, section_count: count).as_json)
        end
      end
    end
  end
end

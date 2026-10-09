# frozen_string_literal: true

module Api
  module V1
    module Catalog
      # GET /api/v1/catalog/terms
      class TermsController < Api::V1::PublicController
        # ?active=true lists only the terms that are in session today.
        def index
          terms  = (boolean_param(:active) ? Term.active : Term.reverse_chronological).to_a
          counts = Course.active.group(:term_id).count

          render_collection(
            terms.map { |term| ::Catalog::TermSerializer.new(term, section_count: counts.fetch(term.id, 0)).as_json },
            meta: { count: terms.size }
          )
        end

        def show
          # find_by! would put its SQL condition in the message, and the client
          # sees the message.
          term = Term.find_by(uid: params[:uid])
          raise ActiveRecord::RecordNotFound, "No term #{params[:uid]}" if term.nil?

          render_term(term)
        end

        # GET /api/v1/catalog/terms/current
        def current
          term = Term.current
          raise ActiveRecord::RecordNotFound, "No current term" if term.nil?

          render_term(term)
        end

        # GET /api/v1/catalog/terms/next
        def next
          term = Term.next
          raise ActiveRecord::RecordNotFound, "No next term" if term.nil?

          render_term(term)
        end

        private

        def render_term(term)
          count = Course.active.where(term_id: term.id).count

          render_resource(::Catalog::TermSerializer.new(term, section_count: count).as_json)
        end
      end
    end
  end
end

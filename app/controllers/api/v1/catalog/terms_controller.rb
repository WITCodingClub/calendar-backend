# frozen_string_literal: true

module Api
  module V1
    module Catalog
      class TermsController < Api::V1::PublicController
        # ?active=true lists only the terms that are in session today.
        def index
          terms = (boolean_param(:active) ? Term.active : Term.reverse_chronological).to_a

          render_collection(::Catalog::TermSerializer.collection(terms), meta: { count: terms.size })
        end

        def show
          render_term(Term.find_by_uid!(params[:uid]))
        end

        def current
          term = Term.current
          raise ActiveRecord::RecordNotFound, "No current term" if term.nil?

          render_term(term)
        end

        def next
          term = Term.next
          raise ActiveRecord::RecordNotFound, "No next term" if term.nil?

          render_term(term)
        end

        private

        def render_term(term)
          render_resource(::Catalog::TermSerializer.with_section_count(term))
        end
      end
    end
  end
end

# frozen_string_literal: true

module Api
  # Terms are catalog data, so no action here needs a token.
  class TermsController < BaseController
    def current_and_next
      current_term = Term.current
      render json: {
        current_term: term_json(current_term),
        next_term:    term_json(Term.next(current_term))
      }, status: :ok
    end

    def active
      render json: {
        active_terms: Term.active.map { |term| term_json(term) }
      }, status: :ok
    end

    private

    def term_json(term)
      return nil unless term

      {
        id:         term.uid,
        pub_id:     term.public_id,
        name:       term.name,
        year:       term.year,
        season:     term.season,
        start_date: term.start_date,
        end_date:   term.end_date
      }
    end
  end
end

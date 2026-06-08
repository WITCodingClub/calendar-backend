# frozen_string_literal: true

module Api
  class MiscController < ApiController
    skip_before_action :authenticate_user_from_token!

    def current_terms
      render json: {
        current_term: term_json(Term.current),
        next_term:    term_json(Term.next)
      }, status: :ok
    end

    private

    def term_json(term)
      return nil unless term

      {
        id:         term.id,
        uid:        term.uid,
        name:       term.name,
        year:       term.year,
        season:     term.season,
        start_date: term.start_date,
        end_date:   term.end_date
      }
    end
  end
end

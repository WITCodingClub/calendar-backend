# frozen_string_literal: true

module Api
  class MiscController < ApiController
    skip_before_action :authenticate_user_from_token!, only: [:get_active_terms, :get_current_and_next_terms]
    skip_before_action :check_beta_access,             only: [:get_active_terms, :get_current_and_next_terms]

    def get_current_and_next_terms
      render json: {
        current_term: term_json(Term.current),
        next_term:    term_json(Term.next)
      }, status: :ok
    end

    def get_active_terms
      render json: {
        active_terms: Term.active.map { |term| term_json(term) }
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

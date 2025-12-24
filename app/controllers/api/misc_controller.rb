# frozen_string_literal: true

module Api
  class MiscController < ApiController
    skip_before_action :authenticate_user_from_token!, only: [:get_current_terms]
    skip_before_action :check_beta_access, only: [:get_current_terms]

    def get_current_terms
      current_term = Term.current
      next_term = Term.next

      render json: {
        current_term: term_json(current_term),
        next_term: term_json(next_term)
      }, status: :ok
    end

    private

    def term_json(term)
      return nil if term.nil?

      {
        name: term.name,
        id: term.uid,
        pub_id: term.public_id,
        start_date: term.start_date,
        end_date: term.end_date
      }
    end

  end
end

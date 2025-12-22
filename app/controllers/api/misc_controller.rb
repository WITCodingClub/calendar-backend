# frozen_string_literal: true

module Api
  class MiscController < ApiController
    skip_before_action :authenticate_user_from_token!, only: [:get_current_terms]
    skip_before_action :check_beta_access, only: [:get_current_terms]

    def get_current_terms
      #   returns the current term, and the next term

      current_term = Term.current
      next_term = Term.next

      render json: {
        current_term: {
          name: current_term.name,
          id: current_term.uid,
          pub_id: current_term.public_id,
          start_date: current_term.start_date,
          end_date: current_term.end_date
        },
        next_term: {
          name: next_term.name,
          id: next_term.uid,
          pub_id: next_term.public_id,
          start_date: next_term.start_date,
          end_date: next_term.end_date
        }
      }, status: :ok

    end

  end
end

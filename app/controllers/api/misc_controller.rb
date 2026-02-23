# frozen_string_literal: true

module Api
  class MiscController < ApiController
    skip_before_action :authenticate_user_from_token!, only: [:get_current_terms]
    skip_before_action :check_beta_access, only: [:get_current_terms]

    def get_current_terms
      current_term = Term.current
      next_term = Term.next

      render json: {
        current_term: TermSerializer.new(current_term).as_json,
        next_term: TermSerializer.new(next_term).as_json
      }, status: :ok
    end

  end
end

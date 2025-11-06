module Api
  class MiscController < ApplicationController
    include JsonWebTokenAuthenticatable
    include FeatureFlagGated

    skip_before_action :verify_authenticity_token
    skip_before_action :authenticate_user_from_token!, only: [:get_current_terms]
    skip_before_action :check_beta_access, only: [:get_current_terms]

    def get_current_terms
      #   returns the current term, and the next term

      current_term = Term.current
      next_term = Term.next

      render json: {
        current_term: {
          name: current_term.name,
          id: current_term.uid
        },
        next_term: {
          name: next_term.name,
          id: next_term.uid
        }
      }, status: :ok

    end

  end
end
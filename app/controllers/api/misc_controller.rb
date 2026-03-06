# frozen_string_literal: true

module Api
  class MiscController < ApiController
    skip_before_action :authenticate_user_from_token!, only: [:get_active_terms]
    skip_before_action :check_beta_access, only: [:get_active_terms]

    def get_active_terms
      active_terms = Term.active

      render json: {
        active_terms: active_terms.map { |term| TermSerializer.new(term).as_json }
      }, status: :ok
    end

  end
end

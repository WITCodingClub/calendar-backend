# frozen_string_literal: true

module Api
  class PreferenceVersionsController < BaseController
    authenticate_with_token

    def show
      response.set_header("Cache-Control", "private, no-store")
      render json: { version: PreferenceVersion.for(current_user) }
    end
  end
end

# frozen_string_literal: true

module Api
  class CatchAllController < BaseController
    authenticate_with_token

    def not_found
      render_error "Not found", status: :not_found
    end
  end
end

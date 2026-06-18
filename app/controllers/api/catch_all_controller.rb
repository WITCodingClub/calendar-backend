# frozen_string_literal: true

module Api
  class CatchAllController < ApiController
    def not_found
      render json: { error: "Not found" }, status: :not_found
    end
  end
end

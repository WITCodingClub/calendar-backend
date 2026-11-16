# frozen_string_literal: true

module Auth
  class StatusController < ApplicationController
    def show
      render json: {
        authenticated: user_signed_in?,
        admin: user_signed_in? && current_user.admin_access?
      }
    end
  end
end

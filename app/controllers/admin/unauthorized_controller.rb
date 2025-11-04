# frozen_string_literal: true

module Admin
  class UnauthorizedController < ApplicationController
    def index
      if user_signed_in?
        render :unauthorized, status: :forbidden
      else
        redirect_to new_user_session_path, alert: "Please sign in to access the admin area."
      end
    end

  end
end

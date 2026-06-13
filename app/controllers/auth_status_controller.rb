# frozen_string_literal: true

class AuthStatusController < ApplicationController
  skip_before_action :authenticate_user!, raise: false

  def show
    render json: {
      authenticated: user_signed_in?,
      admin: user_signed_in? && current_user.admin_access?
    }
  end
end

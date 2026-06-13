# frozen_string_literal: true

class OauthController < ApplicationController
  layout "sessions"

  skip_before_action :verify_authenticity_token

  def success
    @email       = params[:email]
    @calendar_id = params[:calendar_id]
  end

  def failure
    @error = params[:error] || "Unknown error occurred"
  end
end

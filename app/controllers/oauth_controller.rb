# frozen_string_literal: true

class OauthController < ApplicationController
  skip_before_action :verify_authenticity_token
  layout "auth"

  def success
    @email = params[:email]
    @calendar_id = params[:calendar_id]
    @background_url = view_context.asset_path("ia-no-logo.png")
  end

  def failure
    @error = params[:error] || "Unknown error occurred"
    @background_url = view_context.asset_path("ia-no-logo.png")
  end

end

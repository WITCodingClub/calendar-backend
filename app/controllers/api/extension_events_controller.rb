# frozen_string_literal: true

module Api
  # Anonymous usage events from the browser extension, counted for Grafana. The
  # request carries no token, and nothing in it identifies a student.
  class ExtensionEventsController < ApiController
    skip_before_action :authenticate_user_from_token!

    def create
      ExtensionUsage.record(
        events:  params.require(:events),
        version: params[:version],
        browser: params[:browser]
      )

      head :no_content
    end
  end
end

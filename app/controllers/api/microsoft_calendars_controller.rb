# frozen_string_literal: true

module Api
  class MicrosoftCalendarsController < ApiController
    # POST /api/user/microsoft_calendar
    #
    # Returns the URL that starts the Microsoft sign-in for calendar sync.
    # Answers 404 while the Microsoft Graph provider is off for this person.
    def create
      authorize current_user, :show?

      unless MicrosoftGraph.enabled_for?(current_user)
        render json: { error: "Microsoft calendar sync is not enabled" }, status: :not_found
        return
      end

      state     = MicrosoftGraph::OauthState.generate(user_id: current_user.id)
      oauth_url = "#{request.base_url}/auth/microsoft_graph?state=#{CGI.escape(state)}"

      render json: { message: "OAuth required", oauth_url: oauth_url }, status: :ok
    end
  end
end

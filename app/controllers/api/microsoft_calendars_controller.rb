# frozen_string_literal: true

module Api
  class MicrosoftCalendarsController < ApiController
    before_action :require_microsoft_graph

    # POST /api/user/microsoft_calendar
    #
    # Returns the URL that starts the Microsoft sign-in for calendar sync.
    # Answers 404 while the Microsoft Graph provider is off for this person.
    # `placement` ("separate" or "primary") says where a first connection puts
    # the course events. The default is "separate".
    def create
      state     = MicrosoftGraph::OauthState.generate(user_id: current_user.id, placement: params[:placement])
      oauth_url = "#{request.base_url}/auth/microsoft_graph?state=#{CGI.escape(state)}"

      render json: { message: "OAuth required", oauth_url: oauth_url }, status: :ok
    end

    # PATCH /api/user/microsoft_calendar
    #
    # Moves the course events of a connected calendar. "primary" puts them in
    # the person's main calendar, where they show as busy. The move runs in a
    # job, so the answer is 202.
    def update
      placement = params[:placement].to_s

      unless CourseCalendar::PLACEMENTS.value?(placement)
        render json: { error: "placement must be separate or primary" }, status: :unprocessable_content
        return
      end

      unless current_user.oauth_credentials.microsoft.exists?
        render json: { error: "No Microsoft calendar is connected" }, status: :not_found
        return
      end

      MicrosoftGraphCalendarPlacementJob.perform_later(current_user, placement)
      render json: { message: "Calendar placement change started", placement: placement }, status: :accepted
    end

    private

    def require_microsoft_graph
      authorize current_user, :show?
      return if MicrosoftGraph.enabled_for?(current_user)

      render json: { error: "Microsoft calendar sync is not enabled" }, status: :not_found
    end
  end
end

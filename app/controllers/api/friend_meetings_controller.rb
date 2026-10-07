# frozen_string_literal: true

module Api
  # Makes a calendar event from a meeting time that the extension suggested.
  # The work is in FriendMeetingCreator, which the one-time meeting link will
  # also use.
  class FriendMeetingsController < ApiController
    before_action :require_friend_meeting_events

    # POST /api/friends/meetings
    def create
      authorize FriendMeeting, :create?

      meeting = FriendMeetingCreator.call(
        user:           current_user,
        title:          params.require(:title),
        start_time:     params.require(:start_time),
        end_time:       params.require(:end_time),
        friend_ids:     params.require(:friend_ids),
        location:       params[:location],
        frequency:      params[:frequency],
        invite_friends: params[:invite_friends]
      )

      providers = FriendMeetingPublisher.new(current_user).calendar_providers
      render json: { meeting: FriendMeetingSerializer.new(meeting, calendar_providers: providers).as_json }, status: :created
    rescue FriendMeetingCreator::Error => e
      render json: { error: e.message }, status: :unprocessable_content
    end

    private

    # Off for everyone until the privacy policy covers friends v6.
    def require_friend_meeting_events
      return if Flipper.enabled?(FlipperFlags::FRIEND_MEETING_EVENTS, current_user)

      render json: { error: "Friend meeting events are not enabled" }, status: :not_found
    end
  end
end

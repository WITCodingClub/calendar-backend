# frozen_string_literal: true

module Api
  # Meetings that a person makes from a time that the extension suggested.
  # The work is in FriendMeetingCreator, FriendMeetingUpdater, and
  # FriendMeetingPublisher, which the one-time meeting link also uses.
  class FriendMeetingsController < ApiController
    MAX_RANGE = 366.days

    before_action :require_friend_meeting_events
    before_action :set_meeting, only: %i[show update destroy]

    # GET /api/friends/meetings?start=&end=
    #
    # The person's own meetings and the ones that invited them, with each
    # occurrence in the range. It reads only the database, so it works for a
    # person who uses only the ICS feed.
    def index
      authorize FriendMeeting, :index?
      range_start, range_end = requested_range

      meetings    = policy_scope(FriendMeeting).overlapping(range_start, range_end)
                                               .includes(:user, :attendees, :publications).to_a
      occurrences = meetings.flat_map do |meeting|
        meeting.occurrences_between(range_start, range_end).map do |starts_at, ends_at|
          FriendMeetingOccurrenceSerializer.new(meeting, starts_at, ends_at).as_json
        end
      end

      render json: {
        meetings:    meetings.sort_by(&:start_time).map { |meeting| serialize(meeting) },
        occurrences: occurrences.sort_by { |occurrence| occurrence[:start_time] }
      }
    end

    # GET /api/friends/meetings/:id
    def show
      authorize @meeting, :show?
      render json: { meeting: serialize(@meeting) }
    end

    # POST /api/friends/meetings
    #
    # A retry with the same Idempotency-Key answers 200 with the first meeting.
    def create
      authorize FriendMeeting, :create?

      meeting = FriendMeetingCreator.call(
        user:            current_user,
        title:           params.require(:title),
        start_time:      params.require(:start_time),
        end_time:        params.require(:end_time),
        friend_ids:      params.require(:friend_ids),
        location:        params[:location],
        frequency:       params[:frequency],
        invite_friends:  params[:invite_friends],
        idempotency_key: request.headers["Idempotency-Key"].presence || params[:idempotency_key],
        destinations:    params.key?(:destinations) ? Array(params[:destinations]) : nil
      )

      render json: { meeting: serialize(meeting) }, status: meeting.previously_new_record? ? :created : :ok
    rescue FriendMeetingCreator::Error => e
      render json: { error: e.message }, status: :unprocessable_content
    end

    # PATCH /api/friends/meetings/:id
    #
    # Changes the whole series. Only the owner can do it.
    def update
      authorize @meeting, :update?

      FriendMeetingUpdater.call(meeting: @meeting, changes: params.permit(*FriendMeetingUpdater::FIELDS).to_h)
      render json: { meeting: serialize(@meeting.reload) }
    rescue FriendMeetingCreator::Error => e
      render json: { error: e.message }, status: :unprocessable_content
    end

    # DELETE /api/friends/meetings/:id
    #
    # The meeting is gone for the person at once. A job deletes the provider
    # events, which sends each invited friend a cancellation.
    def destroy
      authorize @meeting, :destroy?

      @meeting.update!(cancelled_at: Time.current)
      FriendMeetingRemoveJob.perform_later(@meeting)
      head :no_content
    end

    private

    # Off for everyone until the privacy policy covers friends v6.
    def require_friend_meeting_events
      return if Flipper.enabled?(FlipperFlags::FRIEND_MEETING_EVENTS, current_user)

      render json: { error: "Friend meeting events are not enabled" }, status: :not_found
    end

    # A meeting that the person cannot see answers 404, the same as one that
    # does not exist.
    def set_meeting
      @meeting = policy_scope(FriendMeeting).find_by_public_id(params[:id].to_s)
      raise ActiveRecord::RecordNotFound.new(nil, "FriendMeeting") unless @meeting
    end

    def requested_range
      range_start = parse_range_time(params.require(:start), "start")
      range_end   = parse_range_time(params.require(:end), "end")

      raise ActionController::BadRequest, "end must be after start" unless range_end > range_start
      raise ActionController::BadRequest, "the range can be #{MAX_RANGE.in_days.to_i} days at most" if range_end - range_start > MAX_RANGE

      [ range_start, range_end ]
    end

    # A date (2026-10-01) is the start of that day in the meeting zone. A time
    # needs a UTC offset.
    def parse_range_time(value, name)
      value = value.to_s
      zone  = Time.find_zone!(FriendMeeting::LOCAL_TIME_ZONE)
      return zone.parse(Date.iso8601(value).to_s) if value.match?(/\A\d{4}-\d{2}-\d{2}\z/)

      FriendMeetingCreator.parse_time(value, name)
    rescue Date::Error, FriendMeetingCreator::Error
      raise ActionController::BadRequest, "#{name} must be an ISO 8601 date or a time with a UTC offset"
    end

    def serialize(meeting)
      FriendMeetingSerializer.new(meeting, viewer: current_user).as_json
    end
  end
end

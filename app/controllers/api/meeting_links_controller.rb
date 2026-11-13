# frozen_string_literal: true

module Api
  # One-time meeting links (#652) for the extension. The owner makes, lists,
  # and revokes links here. The guest uses the public page, MeetingLinksController.
  class MeetingLinksController < BaseController
    authenticate_with_token

    before_action :require_meeting_links

    # GET /api/meeting_links
    def index
      authorize MeetingLink, :index?

      links = policy_scope(MeetingLink).includes(:friend_meeting).newest_first
      render json: { meeting_links: MeetingLinkSerializer.render_collection(links) }
    end

    # POST /api/meeting_links
    def create
      authorize MeetingLink, :create?

      link = current_user.meeting_links.create!(
        title:            params[:title].to_s.strip.presence,
        starts_on:        parse_date(params.require(:starts_on), "starts_on"),
        ends_on:          parse_date(params.require(:ends_on), "ends_on"),
        duration_minutes: params.require(:duration_minutes),
        expires_at:       parse_time(params[:expires_at])
      )

      render json: { meeting_link: MeetingLinkSerializer.new(link, url: link.url).as_json },
             status: :created
    end

    # DELETE /api/meeting_links/:id
    #
    # Revokes the link. A used link keeps its meeting: delete the event in the
    # calendar to cancel it.
    #
    # With permanent=true, deletes a revoked or expired link, so it leaves the
    # list (#854). An active or used link answers 409.
    def destroy
      link = policy_scope(MeetingLink).find_by_public_id(params[:id])
      return render_not_found unless link

      authorize link, :destroy?
      return delete_permanently(link) if ActiveModel::Type::Boolean.new.cast(params[:permanent])

      link.revoke! unless link.used?
      render json: { meeting_link: MeetingLinkSerializer.new(link).as_json }
    end

    private

    def delete_permanently(link)
      if link.used?
        render_error "A used link keeps its meeting, so it cannot be deleted", status: :conflict, code: "MEETING_LINK_USED"
      elsif link.usable?
        render_error "Revoke the link before you delete it", status: :conflict, code: "MEETING_LINK_ACTIVE"
      else
        link.destroy!
        head :no_content
      end
    end

    # Off for everyone until the privacy policy covers meeting links.
    def require_meeting_links
      return if Flipper.enabled?(FeatureFlags::MEETING_LINKS, current_user)

      render_error "Meeting links are not enabled", status: :not_found
    end

    def parse_date(value, name)
      Date.iso8601(value.to_s)
    rescue Date::Error
      raise ActionController::BadRequest, "#{name} must be an ISO 8601 date"
    end

    # The offset is required, like FriendMeetings::Creator, so the time does not
    # depend on the server's zone.
    def parse_time(value)
      return nil if value.blank?
      raise ArgumentError unless value.to_s.match?(FriendMeetings::Creator::UTC_OFFSET)

      Time.iso8601(value.to_s)
    rescue ArgumentError
      raise ActionController::BadRequest, "expires_at must be an ISO 8601 time with a UTC offset"
    end
  end
end

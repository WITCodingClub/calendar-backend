# frozen_string_literal: true

module Api
  # One-time meeting links (#652) for the extension. The owner makes, lists,
  # and revokes links here. The guest uses the public page, MeetingLinksController.
  class MeetingLinksController < BaseController
    authenticate_with_token

    # Off for everyone until the privacy policy covers meeting links.
    require_feature FeatureFlags::MEETING_LINKS, "Meeting links are not enabled"

    def index
      authorize MeetingLink, :index?

      links = policy_scope(MeetingLink).includes(:friend_meeting).newest_first
      render json: { meeting_links: MeetingLinkSerializer.render_collection(links) }
    end

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

    # A plain DELETE revokes the link. With permanent=true, it deletes a
    # revoked or expired link. An active or used link then answers 409.
    def destroy
      link = policy_scope(MeetingLink).find_by_public_id(params[:id])
      return render_not_found unless link

      authorize link, :destroy?
      permanent = MeetingLinks::Removal.permanent?(params[:permanent])
      result    = MeetingLinks::Removal.call(link, permanent: permanent)

      if result == :deleted
        head :no_content
      elsif result == :active
        render_error "Revoke the link before you delete it", status: :conflict, code: "MEETING_LINK_ACTIVE"
      elsif result == :used && permanent
        render_error "A used link keeps its meeting, so it cannot be deleted", status: :conflict, code: "MEETING_LINK_USED"
      else
        render json: { meeting_link: MeetingLinkSerializer.new(link).as_json }
      end
    end

    private

    def parse_date(value, name)
      Date.iso8601(value.to_s)
    rescue Date::Error
      raise ActionController::BadRequest, "#{name} must be an ISO 8601 date"
    end

    def parse_time(value)
      return nil if value.blank?

      Friendships::OffsetTime.parse(value) ||
        raise(ActionController::BadRequest, "expires_at must be an ISO 8601 time with a UTC offset")
    end
  end
end

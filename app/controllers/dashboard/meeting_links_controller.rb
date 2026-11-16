# frozen_string_literal: true

module Dashboard
  # The owner's page for one-time meeting links (#652): make a link, see the
  # links and their bookings, and revoke a link.
  class MeetingLinksController < Dashboard::ApplicationController
    # The new link's URL, kept for one page view. The flash would show it in a
    # banner that closes after five seconds.
    NEW_URL_KEY = :new_meeting_link_url

    require_feature FeatureFlags::MEETING_LINKS, "Meeting links are not enabled"
    after_action :verify_policy_scoped, only: :index

    def index
      authorize MeetingLink, :index?

      @links   = policy_scope(MeetingLink).includes(:friend_meeting).newest_first
      @new_url = session.delete(NEW_URL_KEY)
      @link    = MeetingLink.new(starts_on: Time.zone.tomorrow, ends_on: Time.zone.tomorrow + 13, duration_minutes: 30)
    end

    def create
      authorize MeetingLink, :create?

      permitted  = link_params
      expires_on = permitted.delete(:expires_on).presence
      expires_at = expires_on && Friendships::ExpiryTime.parse(expires_on)
      return redirect_to(dashboard_meeting_links_path, alert: "Expiry date must be a date.") if expires_on && !expires_at

      link = current_user.meeting_links.new(permitted.merge(expires_at:))
      if link.save
        session[NEW_URL_KEY] = link.url
        redirect_to dashboard_meeting_links_path, notice: "Link made. Copy it now: it is shown only once."
      else
        redirect_to dashboard_meeting_links_path, alert: link.errors.full_messages.to_sentence
      end
    end

    def destroy
      # The scope is the access check: another person's link finds nothing.
      link = policy_scope(MeetingLink).find_by_public_id(params[:id])
      unless link
        skip_authorization
        return redirect_to(dashboard_meeting_links_path, alert: "Link not found.")
      end

      authorize link, :destroy?

      result = MeetingLinks::Removal.call(link, permanent: MeetingLinks::Removal.permanent?(params[:permanent]))
      if result.changed?
        redirect_to dashboard_meeting_links_path, notice: "Link #{result.outcome}."
      else
        redirect_to dashboard_meeting_links_path, alert: "#{result.refusal.message}."
      end
    end

    private

    # The form asks for an expiry date. The link works until the end of that
    # day (Friendships::ExpiryTime). With no date, the model uses the end of
    # the last day in the range.
    def link_params
      permitted = params.expect(meeting_link: [ :title, :starts_on, :ends_on, :duration_minutes, :expires_on ])
      permitted.merge(title: permitted[:title].to_s.strip.presence)
    end
  end
end

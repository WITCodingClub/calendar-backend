# frozen_string_literal: true

module Dashboard
  # The owner's page for one-time meeting links (#652): make a link, see the
  # links and their bookings, and revoke a link.
  class MeetingLinksController < Dashboard::ApplicationController
    # The new link's URL, kept for one page view. The flash would show it in a
    # banner that closes after five seconds.
    NEW_URL_KEY = :new_meeting_link_url

    before_action :require_meeting_links
    after_action :verify_policy_scoped, only: :index

    def index
      authorize MeetingLink, :index?

      @links   = policy_scope(MeetingLink).includes(:friend_meeting).newest_first
      @new_url = session.delete(NEW_URL_KEY)
      @link    = MeetingLink.new(starts_on: Time.zone.tomorrow, ends_on: Time.zone.tomorrow + 13, duration_minutes: 30)
    end

    def create
      authorize MeetingLink, :create?

      link = current_user.meeting_links.new(link_params)
      if link.save
        session[NEW_URL_KEY] = link.url
        redirect_to dashboard_meeting_links_path, notice: "Link made. Copy it now: it is shown only once."
      else
        redirect_to dashboard_meeting_links_path, alert: link.errors.full_messages.to_sentence
      end
    end

    # Revokes the link. A used link keeps its meeting.
    def destroy
      # The scope is the access check: another person's link finds nothing.
      link = policy_scope(MeetingLink).find_by_public_id(params[:id])
      unless link
        skip_authorization
        return redirect_to(dashboard_meeting_links_path, alert: "Link not found.")
      end

      authorize link, :destroy?
      if link.used?
        redirect_to dashboard_meeting_links_path, alert: "This link was already used. Delete the event in your calendar to cancel the meeting."
      else
        link.revoke!
        redirect_to dashboard_meeting_links_path, notice: "Link revoked."
      end
    end

    private

    def require_meeting_links
      head :not_found unless Flipper.enabled?(FeatureFlags::MEETING_LINKS, current_user)
    end

    # The form asks for an expiry date. The link works until the end of that
    # day. With no date, the model uses the end of the last day in the range.
    def link_params
      permitted  = params.expect(meeting_link: [ :title, :starts_on, :ends_on, :duration_minutes, :expires_on ])
      expires_on = permitted.delete(:expires_on)
      permitted.merge(title: permitted[:title].to_s.strip.presence, expires_at: end_of_day(expires_on))
    end

    def end_of_day(value)
      Date.iso8601(value.to_s).in_time_zone.end_of_day if value.present?
    rescue Date::Error
      nil
    end
  end
end

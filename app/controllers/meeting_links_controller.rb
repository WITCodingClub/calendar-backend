# frozen_string_literal: true

# The public page of a one-time meeting link (#652). Anyone with the link can
# open it. Sign-in is optional: a signed-in guest sees only the times when both
# people are free.
#
# The page shows free times and the owner's name, and nothing else. A link
# that is unknown, expired, used, or revoked, or whose owner does not have the
# flag, gets the same "no longer works" page with the same status, so the page
# never says whether a token existed.
class MeetingLinksController < ApplicationController
  layout "public"

  # The session key that brings a guest back to the link after sign-in.
  RETURN_TO_KEY = :meeting_link_return_to
  # The session key that lets the guest who booked see the confirmation.
  BOOKED_KEY = :booked_meeting_link_id

  before_action :hide_token_from_other_sites
  before_action :find_link

  # GET /meet/:token
  def show
    return render_booked if booked_by_this_browser?
    return render_gone unless usable?

    load_slots
  end

  # POST /meet/:token
  def create
    return render_gone unless usable?
    return redirect_to(meeting_link_path(params[:token])) if owner_viewing?

    MeetingLinkBooking.call(
      link:        @link,
      start_time:  params[:start_time],
      guest_name:  params[:name],
      guest_email: params[:email],
      guest_user:  current_user
    )

    session[BOOKED_KEY] = @link.id
    redirect_to meeting_link_path(params[:token])
  rescue MeetingLinkBooking::Gone
    render_gone
  rescue MeetingLinkBooking::Invalid => e
    @error = e.message
    load_slots
    render :show, status: :unprocessable_content
  end

  # GET /meet/:token/sign_in
  #
  # Remembers the link, then sends the guest to the sign-in page. After
  # sign-in, ApplicationController#after_sign_in_path_for sends them back.
  def start_sign_in
    return render_gone unless usable?

    session[RETURN_TO_KEY] = meeting_link_path(params[:token])
    redirect_to new_user_session_path
  end

  private

  # The token is in the path, so a link on this page must not send it to
  # another site in the Referer header, and search engines must not keep it.
  def hide_token_from_other_sites
    response.set_header("Referrer-Policy", "no-referrer")
    response.set_header("X-Robots-Tag", "noindex, nofollow")
  end

  def find_link
    @link = MeetingLink.includes(:user).find_by_token(params[:token])
  end

  def usable?
    @link.present? && @link.usable? && Flipper.enabled?(FlipperFlags::MEETING_LINKS, @link.user)
  end

  def owner_viewing?
    user_signed_in? && current_user.id == @link.user_id
  end

  def booked_by_this_browser?
    @link.present? && @link.used? && session[BOOKED_KEY] == @link.id && @link.friend_meeting.present?
  end

  def load_slots
    @owner        = @link.user
    @owner_view   = owner_viewing?
    @guest        = current_user unless @owner_view
    @slots_by_day = MeetingLinkSlots.new(@link, guest: @guest).call.group_by(&:date)
  end

  def render_booked
    @meeting = @link.friend_meeting
    @owner   = @link.user
    render :booked
  end

  def render_gone
    render :gone, status: :not_found
  end
end

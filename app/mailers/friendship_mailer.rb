# frozen_string_literal: true

# Friend emails. A user turns them off with users.friend_emails on the
# notifications page. The check runs when the email is built, so an email that
# was queued before the user turned them off is not sent either.
class FriendshipMailer < ApplicationMailer
  EXPIRY_EVENTS = %w[shortened proposed proposal_accepted proposal_declined].freeze

  before_action { @preferences_url = dashboard_notifications_url(anchor: "emails") }

  def request_received(friendship)
    @friendship = friendship
    @requester  = friendship.requester
    @addressee  = friendship.addressee
    @requests_url = dashboard_friends_requests_url
    return unless @addressee.friend_emails?

    mail(
      to: @addressee.email,
      subject: "#{@requester.full_name} sent you a friend request on WIT Calendar"
    )
  end

  # Tells the other user that `actor` changed the end date of their friendship
  # or request. `event` is one of EXPIRY_EVENTS.
  def expiry_changed(friendship, actor, event)
    raise ArgumentError, "unknown expiry event #{event}" unless EXPIRY_EVENTS.include?(event)

    @friendship  = friendship
    @actor       = actor
    @recipient   = friendship.friend_for(actor)
    return unless @recipient.friend_emails?

    @event       = event
    @friends_url = friendship.pending? ? dashboard_friends_requests_url : dashboard_friends_url
    @link_text   = event == "proposed" ? "Accept or decline the proposal" : "Manage your friends"
    @summary     = expiry_summary

    mail(to: @recipient.email, subject: expiry_subject)
  end

  private

  def expiry_summary
    name = @actor.full_name

    case @event
    when "shortened"
      "#{name} made your friendship end sooner. It now ends on #{long_date(@friendship.expires_at)}."
    when "proposed"
      proposal = @friendship.proposed_permanent? ? "a permanent friendship" : "a new end date: #{long_date(@friendship.proposed_expires_at)}"
      "#{name} proposed #{proposal}. Nothing changes until you accept it on the WIT Calendar dashboard."
    when "proposal_accepted"
      result = @friendship.temporary? ? "now ends on #{long_date(@friendship.expires_at)}" : "is now permanent"
      "#{name} accepted your proposal. The friendship #{result}."
    when "proposal_declined"
      "#{name} declined your proposal. The end date did not change."
    end
  end

  def long_date(time) = time.to_date.to_fs(:long)

  def expiry_subject
    case @event
    when "shortened"         then "#{@actor.full_name} changed the end date of your friendship"
    when "proposed"          then "#{@actor.full_name} proposed a new end date for your friendship"
    when "proposal_accepted" then "#{@actor.full_name} accepted the new end date for your friendship"
    when "proposal_declined" then "#{@actor.full_name} declined the new end date for your friendship"
    end
  end
end

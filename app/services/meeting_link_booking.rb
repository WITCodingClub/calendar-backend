# frozen_string_literal: true

# Books the one time that a meeting link allows.
#
# The booking locks (SELECT ... FOR UPDATE) the user rows of the owner and of
# a signed-in guest, in id order, and then the link row, for the whole
# booking. Two guests who pick at the same moment wait for each other: on one
# link the second finds the link used, and on two links of the same owner the
# second finds the slot taken, because the slot check runs inside the lock
# and reads the owner's meetings.
#
# The guest row is locked too, because saving the link checks its foreign
# key, which takes a key share lock on the guest row. Without it, two people
# who book each other's links at the same moment could deadlock. With every
# booking locking user rows in id order, they wait instead. If Postgres still
# reports a deadlock, the booking raises Invalid and the guest can try again.
#
# The meeting itself is made by FriendMeetingCreator, with the guest as the
# one invitee, so it reaches the owner's calendars by the same path as a
# meeting with friends.
#
# Raises Gone when the link cannot be used, and Invalid when the request is
# wrong. A Gone error says nothing about why, so the page cannot tell a guest
# whether a token ever existed.
class MeetingLinkBooking < ApplicationService
  class Error < StandardError; end
  class Gone < Error; end
  class Invalid < Error; end

  EMAIL_FORMAT = URI::MailTo::EMAIL_REGEXP

  def initialize(link:, start_time:, guest_name:, guest_email:, guest_user: nil)
    @link        = link
    @start_time  = start_time
    @guest_name  = guest_name.to_s.squish
    @guest_email = guest_email.to_s.strip.downcase
    @guest_user  = guest_user
  end

  def call
    validate_guest!
    start = parse_start

    MeetingLink.transaction do
      User.where(id: [ @link.user_id, @guest_user&.id ].compact.uniq).order(:id).lock.to_a
      link = MeetingLink.lock.find(@link.id)
      raise Gone unless link.usable? && Flipper.enabled?(FlipperFlags::MEETING_LINKS, link.user)

      slot = MeetingLinkSlots.new(link, guest: @guest_user).find(start)
      raise Invalid, "That time is no longer free. Pick another time." unless slot

      meeting = FriendMeetingCreator.call(
        user:       link.user,
        title:      link.meeting_title(@guest_name),
        start_time: slot.start_time.iso8601,
        end_time:   slot.end_time.iso8601,
        friend_ids: [],
        guest:      { name: @guest_name, email: @guest_email }
      )
      link.update!(used_at: Time.current, friend_meeting: meeting, guest_user: @guest_user)

      ActiveRecord.after_all_transactions_commit { MeetingLinkMailer.booked(link).deliver_later }
      link
    end
  rescue FriendMeetingCreator::Error, ActiveRecord::RecordInvalid => e
    raise Invalid, e.message
  rescue ActiveRecord::Deadlocked
    raise Invalid, "Another booking happened at the same moment. Pick your time again."
  end

  private

  def validate_guest!
    raise Invalid, "Enter your name." if @guest_name.blank?
    raise Invalid, "Your name must be #{FriendMeeting::GUEST_NAME_MAX_LENGTH} characters or fewer." if @guest_name.length > FriendMeeting::GUEST_NAME_MAX_LENGTH
    raise Invalid, "Enter a valid email address." unless @guest_email.match?(EMAIL_FORMAT)
  end

  def parse_start
    Time.iso8601(@start_time.to_s).in_time_zone
  rescue ArgumentError
    raise Invalid, "Pick a time."
  end
end

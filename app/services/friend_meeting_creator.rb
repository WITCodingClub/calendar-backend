# frozen_string_literal: true

# Makes a FriendMeeting from a time that the person picked, and starts the job
# that puts it in their calendars.
#
# The API route for suggested meeting times calls it, and so does the
# one-time meeting link (#652), so every check lives here and not in a
# controller.
#
# A meeting link passes a guest: { name:, email: } and no friends. The guest
# is not a user of the app, so no friend check applies to it. The guest always
# gets the invitation, whatever invite_friends says.
#
# With an idempotency key, a second call with the same key for the same person
# returns the first meeting. It makes no new meeting and starts no job, so no
# friend gets a second invitation. The caller can tell the two apart with
# `previously_new_record?`.
#
# Raises FriendMeetingCreator::Error for a request that cannot become a
# meeting, and ActiveRecord::RecordInvalid when the meeting fails validation.
class FriendMeetingCreator < ApplicationService
  class Error < StandardError; end

  UTC_OFFSET = /(?:Z|[+-]\d{2}:?\d{2})\z/

  def initialize(user:, title:, start_time:, end_time:, friend_ids:, location: nil,
                 frequency: nil, invite_friends: false, idempotency_key: nil, destinations: nil, guest: nil)
    @user            = user
    @title           = title
    @start_time      = start_time
    @end_time        = end_time
    @friend_ids      = friend_ids
    @location        = location
    @frequency       = frequency.presence || FriendMeeting::FREQUENCIES[:one_time]
    @invite_friends  = ActiveModel::Type::Boolean.new.cast(invite_friends) || false
    @idempotency_key = idempotency_key.to_s.strip.presence
    @destinations    = destinations
    @guest           = guest
  end

  def call
    existing = find_existing
    return existing if existing

    raise Error, "frequency must be one_time or weekly" unless FriendMeeting::FREQUENCIES.value?(@frequency)

    friends      = resolve_friends
    destinations = resolve_destinations
    meeting      = FriendMeeting.new(
      user:            @user,
      title:           @title.to_s.strip,
      location:        @location.to_s.strip.presence,
      start_time:      self.class.parse_time(@start_time, "start_time"),
      end_time:        self.class.parse_time(@end_time, "end_time"),
      frequency:       @frequency,
      invite_friends:  @invite_friends,
      idempotency_key: @idempotency_key,
      guest_name:      @guest && @guest[:name].to_s.strip,
      guest_email:     @guest && @guest[:email].to_s.strip.downcase
    )
    self.class.assign_term(meeting) if meeting.weekly?

    FriendMeeting.transaction do
      meeting.save!
      friends.each { |friend| meeting.friend_meeting_attendees.create!(user: friend) }
      create_publications(meeting, destinations)
    end

    # A meeting link calls this inside its own transaction. The job must not
    # run before that commits, or it finds no meeting.
    if meeting.publications.any?(&:calendar?)
      ActiveRecord.after_all_transactions_commit { FriendMeetingPublishJob.perform_later(meeting) }
    end
    meeting
  rescue ActiveRecord::RecordNotUnique
    # A request with the same key won the race.
    find_existing || raise
  end

  # The offset is required: without it, the time would depend on the server's
  # zone and not on the person's.
  def self.parse_time(value, name)
    value = value.to_s
    raise ArgumentError unless value.match?(UTC_OFFSET)

    Time.iso8601(value).in_time_zone
  rescue ArgumentError
    raise Error, "#{name} must be an ISO 8601 time with a UTC offset"
  end

  # A weekly meeting repeats until the end of the term that holds its first
  # day. Between terms, that is the current term, which must not have ended.
  def self.assign_term(meeting)
    start_date = meeting.local_start.to_date
    term       = Term.find_by_date(start_date) || Term.current

    if term.nil? || term.end_date.nil? || term.end_date < start_date
      raise Error, "a weekly meeting must start on or before the last day of the current term"
    end

    meeting.term         = term
    meeting.repeat_until = term.end_date
  end

  private

  def find_existing
    return nil unless @idempotency_key

    @user.friend_meetings.find_by(idempotency_key: @idempotency_key)
  end

  # Every id must be a friend whose request was accepted. One that is not
  # stops the request, so a person can never invite a stranger by user id.
  # Only a meeting link, which brings its own guest, can list no friends.
  def resolve_friends
    ids = Array(@friend_ids).map(&:to_s).map(&:strip).compact_blank.uniq
    return [] if ids.empty? && @guest

    raise Error, "friend_ids must list at least one friend" if ids.empty?
    raise Error, "friend_ids can list no more than #{FriendMeeting::MAX_ATTENDEES} friends" if ids.size > FriendMeeting::MAX_ATTENDEES

    friends = @user.friends
    ids.map do |id|
      public_id = id.include?("_") ? id : "usr_#{id}"
      friends.find_by_public_id(public_id) || raise(Error, "#{id} is not one of your accepted friends")
    end.uniq
  end

  # Without a list, the meeting goes to every connected course calendar and
  # the ICS feed. A list may name only those places.
  def resolve_destinations
    allowed = FriendMeetingPublisher.new(@user).calendar_providers + [ FriendMeetingPublication::PROVIDERS[:ics] ]
    return allowed if @destinations.nil?

    picked = Array(@destinations).map { |name| name.to_s.strip.downcase }.compact_blank.uniq
    raise Error, "destinations must list at least one place" if picked.empty?

    unknown = picked - allowed
    raise Error, "destinations can list only #{allowed.join(', ')}; not #{unknown.join(', ')}" if unknown.any?

    picked
  end

  # Invitations go out from the first picked provider that can send them. The
  # ICS feed cannot, so it never does. A guest always gets one.
  def create_publications(meeting, destinations)
    invites = meeting.invite_friends? || meeting.guest_email?
    sender  = (destinations & FriendMeetingPublication::CALENDAR_PROVIDERS).first if invites

    destinations.each do |provider|
      meeting.publications.create!(
        provider:          provider,
        status:            provider == FriendMeetingPublication::PROVIDERS[:ics] ? "published" : "queued",
        sends_invitations: provider == sender
      )
    end
  end
end

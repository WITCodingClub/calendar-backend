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
# Raises FriendMeetingCreator::Error for a request that cannot become a
# meeting, and ActiveRecord::RecordInvalid when the meeting fails validation.
class FriendMeetingCreator < ApplicationService
  class Error < StandardError; end

  UTC_OFFSET = /(?:Z|[+-]\d{2}:?\d{2})\z/

  def initialize(user:, title:, start_time:, end_time:, friend_ids:, location: nil,
                 frequency: nil, invite_friends: false, guest: nil)
    @user           = user
    @title          = title
    @start_time     = start_time
    @end_time       = end_time
    @friend_ids     = friend_ids
    @location       = location
    @frequency      = frequency.presence || FriendMeeting::FREQUENCIES[:one_time]
    @invite_friends = ActiveModel::Type::Boolean.new.cast(invite_friends) || false
    @guest          = guest
  end

  def call
    raise Error, "frequency must be one_time or weekly" unless FriendMeeting::FREQUENCIES.value?(@frequency)

    friends  = resolve_friends
    starts   = parse_time(@start_time, "start_time")
    ends     = parse_time(@end_time, "end_time")
    meeting  = FriendMeeting.new(
      user:           @user,
      title:          @title.to_s.strip,
      location:       @location.to_s.strip.presence,
      start_time:     starts,
      end_time:       ends,
      frequency:      @frequency,
      invite_friends: @invite_friends,
      guest_name:     @guest && @guest[:name].to_s.strip,
      guest_email:    @guest && @guest[:email].to_s.strip.downcase
    )
    assign_term(meeting) if meeting.weekly?

    FriendMeeting.transaction do
      meeting.save!
      friends.each { |friend| meeting.friend_meeting_attendees.create!(user: friend) }
    end

    # A meeting link calls this inside its own transaction. The job must not
    # run before that commits, or it finds no meeting.
    ActiveRecord.after_all_transactions_commit { FriendMeetingPublishJob.perform_later(meeting) }
    meeting
  end

  private

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

  # The offset is required: without it, the time would depend on the server's
  # zone and not on the person's.
  def parse_time(value, name)
    value = value.to_s
    raise ArgumentError unless value.match?(UTC_OFFSET)

    Time.iso8601(value).in_time_zone
  rescue ArgumentError
    raise Error, "#{name} must be an ISO 8601 time with a UTC offset"
  end

  # A weekly meeting repeats until the end of the term that holds its first
  # day. Between terms, that is the current term, which must not have ended.
  def assign_term(meeting)
    start_date = meeting.local_start.to_date
    term       = Term.find_by_date(start_date) || Term.current

    if term.nil? || term.end_date.nil? || term.end_date < start_date
      raise Error, "a weekly meeting must start on or before the last day of the current term"
    end

    meeting.term         = term
    meeting.repeat_until = term.end_date
  end
end

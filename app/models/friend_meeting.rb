# frozen_string_literal: true

# == Schema Information
#
# Table name: friend_meetings
#
#  id             :bigint           not null, primary key
#  end_time       :datetime         not null
#  frequency      :string           default("one_time"), not null
#  guest_email    :string
#  guest_name     :string
#  invite_friends :boolean          default(FALSE), not null
#  location       :string
#  repeat_until   :date
#  start_time     :datetime         not null
#  title          :string           not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  term_id        :bigint
#  user_id        :bigint           not null
#
# Indexes
#
#  index_friend_meetings_on_term_id  (term_id)
#  index_friend_meetings_on_user_id  (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (term_id => terms.id)
#  fk_rails_...  (user_id => users.id)
#
# A meeting that a person makes from a time when they and some friends are
# free. The extension suggests the time; the person picks one.
#
# The meeting is its own record, not a course event, so a course sync never
# deletes it and the ICS feed can show it. Each provider event for the meeting
# is a CalendarEvent row in the person's course calendar, so the existing
# remote delete and cleanup code tracks it like a course event.
class FriendMeeting < ApplicationRecord
  include EncodedIds::HashidIdentifiable

  set_public_id_prefix :fmt, min_hash_length: 12

  LOCAL_TIME_ZONE  = "America/New_York"
  MAX_DURATION     = 12.hours
  MAX_ATTENDEES    = 20
  TITLE_MAX_LENGTH = 200

  FREQUENCIES = { one_time: "one_time", weekly: "weekly" }.freeze

  GUEST_NAME_MAX_LENGTH = 100

  # A person who is not a user of the app. A one-time meeting link (#652)
  # adds one. It answers to the same email and full_name calls as a User, so
  # the provider services and the ICS feed invite it like a friend.
  Guest = Data.define(:email, :full_name)

  enum :frequency, FREQUENCIES, validate: true

  belongs_to :user
  belongs_to :term, optional: true
  has_many :friend_meeting_attendees, dependent: :delete_all
  has_many :attendees, through: :friend_meeting_attendees, source: :user
  # Each row deletes its own provider event when it is destroyed.
  has_many :calendar_events, dependent: :destroy

  validates :title, presence: true, length: { maximum: TITLE_MAX_LENGTH }
  validates :location, length: { maximum: TITLE_MAX_LENGTH }
  validates :start_time, :end_time, presence: true
  validates :term, :repeat_until, presence: true, if: :weekly?
  validates :guest_name, length: { maximum: GUEST_NAME_MAX_LENGTH }
  validates :guest_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_nil: true
  validates :guest_name, presence: true, if: :guest_email?
  validate :end_time_after_start_time
  validate :repeat_until_on_or_after_start

  # A meeting stays in the feed and the sync until its last occurrence ends.
  scope :not_ended, lambda {
    where(end_time: Time.current..)
      .or(where(frequency: "weekly", repeat_until: Time.zone.today..))
  }

  # The event hash that the provider services take, in the same shape as a
  # course event from CourseScheduleSyncable.
  def event_data
    {
      summary:    title,
      location:   location.presence,
      start_time: start_time,
      end_time:   end_time,
      recurrence: recurrence,
      all_day:    false
    }
  end

  # A weekly meeting repeats on its start day until the end of repeat_until in
  # local time. UNTIL is that moment in UTC, like a course RRULE, so a late
  # meeting keeps its last occurrence.
  def recurrence
    return nil unless weekly? && repeat_until && start_time

    until_time = Time.find_zone!(LOCAL_TIME_ZONE).local(repeat_until.year, repeat_until.month, repeat_until.day, 23, 59, 59).utc
    rule       = IceCube::Rule.weekly.day(local_start.strftime("%A").downcase.to_sym).until(until_time)
    [ "RRULE:#{rule.to_ical}" ]
  end

  def local_start
    start_time.in_time_zone(LOCAL_TIME_ZONE)
  end

  # The people that get an invitation: the friends, if the person asked for
  # it, and the guest from a meeting link, who always gets one.
  def invitees
    friends = invite_friends? ? attendees.to_a : []
    guest_email? ? friends + [ Guest.new(email: guest_email, full_name: guest_name) ] : friends
  end

  private

  def end_time_after_start_time
    return if start_time.blank? || end_time.blank?

    if end_time <= start_time
      errors.add(:end_time, "must be after the start time")
    elsif end_time - start_time > MAX_DURATION
      errors.add(:end_time, "must be no more than 12 hours after the start time")
    end
  end

  def repeat_until_on_or_after_start
    return if repeat_until.blank? || start_time.blank?
    return if repeat_until >= local_start.to_date

    errors.add(:repeat_until, "must be on or after the start date")
  end
end

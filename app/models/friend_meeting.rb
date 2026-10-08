# frozen_string_literal: true

# == Schema Information
#
# Table name: friend_meetings
#
#  id              :bigint           not null, primary key
#  cancelled_at    :datetime
#  end_time        :datetime         not null
#  frequency       :string           default("one_time"), not null
#  guest_email     :string
#  guest_name      :string
#  idempotency_key :string
#  invite_friends  :boolean          default(FALSE), not null
#  location        :string
#  repeat_until    :date
#  start_time      :datetime         not null
#  title           :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  term_id         :bigint
#  user_id         :bigint           not null
#
# Indexes
#
#  idx_friend_meetings_unique_idempotency_key  (user_id,idempotency_key) UNIQUE WHERE (idempotency_key IS NOT NULL)
#  index_friend_meetings_on_term_id            (term_id)
#  index_friend_meetings_on_user_id            (user_id)
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
  IDEMPOTENCY_KEY_MAX_LENGTH = 255

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
  has_many :publications, class_name: "FriendMeetingPublication", dependent: :delete_all

  validates :title, presence: true, length: { maximum: TITLE_MAX_LENGTH }
  validates :location, length: { maximum: TITLE_MAX_LENGTH }
  validates :start_time, :end_time, presence: true
  validates :term, :repeat_until, presence: true, if: :weekly?
  validates :guest_name, length: { maximum: GUEST_NAME_MAX_LENGTH }
  validates :guest_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_nil: true
  validates :guest_name, presence: true, if: :guest_email?
  validates :idempotency_key, length: { maximum: IDEMPOTENCY_KEY_MAX_LENGTH }
  validate :end_time_after_start_time
  validate :repeat_until_on_or_after_start

  # A meeting stays in the feed and the sync until its last occurrence ends.
  scope :not_ended, lambda {
    where(end_time: Time.current..)
      .or(where(frequency: "weekly", repeat_until: Time.zone.today..))
  }

  # A meeting that the owner deleted stays until its provider events are gone.
  # Every read and sync skips it, so nothing puts it back.
  scope :live, -> { where(cancelled_at: nil) }

  # The meetings that invited `user`: the owner asked to invite the friends,
  # and `user` is one of them.
  scope :inviting, lambda { |user|
    where(invite_friends: true).where(id: FriendMeetingAttendee.where(user_id: user.id).select(:friend_meeting_id))
  }

  # Meetings with at least one occurrence that overlaps the range.
  scope :overlapping, lambda { |range_start, range_end|
    where(start_time: ...range_end)
      .and(where(end_time: range_start..).or(where(frequency: "weekly", repeat_until: range_start.to_date..)))
  }

  def cancelled? = cancelled_at.present?

  def owned_by?(person) = person.present? && user_id == person.id

  def invited?(person)
    person.present? && invite_friends? && friend_meeting_attendees.exists?(user_id: person.id)
  end

  def publication_for(provider)
    publications.find { |publication| publication.provider == provider.to_s }
  end

  # The providers that the person picked, in their order.
  def destinations
    publications.sort_by(&:id).map(&:provider)
  end

  # Each occurrence that overlaps the range, as [start, end] pairs. A weekly
  # meeting keeps its local wall time across a daylight saving change.
  def occurrences_between(range_start, range_end)
    duration = end_time - start_time
    starts =
      if weekly?
        schedule = IceCube::Schedule.new(local_start, duration: duration)
        schedule.add_recurrence_rule(IceCube::Rule.weekly.day(local_start.strftime("%A").downcase.to_sym).until(recurrence_until))
        schedule.occurrences_between(range_start, range_end, spans: true)
      else
        [ local_start ]
      end

    starts.filter_map do |starts_at|
      ends_at = starts_at + duration
      [ starts_at, ends_at ] if starts_at < range_end && ends_at > range_start
    end
  end

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

    rule = IceCube::Rule.weekly.day(local_start.strftime("%A").downcase.to_sym).until(recurrence_until.utc)
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

  def recurrence_until
    Time.find_zone!(LOCAL_TIME_ZONE).local(repeat_until.year, repeat_until.month, repeat_until.day, 23, 59, 59)
  end

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

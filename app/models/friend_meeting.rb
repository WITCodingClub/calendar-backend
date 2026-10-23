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
#  repeat_days     :string           default([]), not null, is an Array
#  repeat_interval :integer          default(1), not null
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

  FREQUENCIES = { one_time: "one_time", daily: "daily", weekly: "weekly", monthly: "monthly" }.freeze

  # A repeating meeting happens every repeat_interval days, weeks, or months.
  MAX_REPEAT_INTERVAL = 30
  # The last occurrence can start up to a year after the first.
  MAX_REPEAT_LENGTH = 366.days
  WEEKDAYS = %w[sunday monday tuesday wednesday thursday friday saturday].freeze
  # The ordinal of a weekday in its month for a monthly rule. The fifth one is
  # not in every month, so it becomes the last one.
  MONTHLY_WEEKS = { 1 => 1, 2 => 2, 3 => 3, 4 => 4, 5 => -1 }.freeze

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
  validates :term, :repeat_until, presence: true, if: :repeating?
  validates :repeat_interval, numericality: { only_integer: true, in: 1..MAX_REPEAT_INTERVAL }
  validates :guest_name, length: { maximum: GUEST_NAME_MAX_LENGTH }
  validates :guest_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_nil: true
  validates :guest_name, presence: true, if: :guest_email?
  validates :idempotency_key, length: { maximum: IDEMPOTENCY_KEY_MAX_LENGTH }
  validate :end_time_after_start_time
  validate :repeat_until_on_or_after_start
  validate :repeat_days_are_weekdays

  # A meeting stays in the feed and the sync until its last occurrence ends.
  scope :not_ended, lambda {
    where(end_time: Time.current..)
      .or(where.not(frequency: "one_time").where(repeat_until: Time.zone.today..))
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
      .and(where(end_time: range_start..).or(where.not(frequency: "one_time").where(repeat_until: range_start.to_date..)))
  }

  def cancelled? = cancelled_at.present?

  def repeating? = frequency.present? && !one_time?

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

  # Each occurrence that overlaps the range, as [start, end] pairs. A
  # repeating meeting keeps its local wall time across a daylight saving change.
  def occurrences_between(range_start, range_end)
    duration = end_time - start_time
    starts =
      if repeating?
        schedule = IceCube::Schedule.new(local_start, duration: duration)
        schedule.add_recurrence_rule(recurrence_rule.until(recurrence_until))
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

  # A repeating meeting repeats until the end of repeat_until in local time.
  # UNTIL is that moment in UTC, like a course RRULE, so a late meeting keeps
  # its last occurrence.
  def recurrence
    return nil unless repeating? && repeat_until && start_time

    [ "RRULE:#{recurrence_rule.until(recurrence_until.utc).to_ical}" ]
  end

  # The days of a weekly meeting, in week order. The day of the first
  # occurrence is always one of them, so the series starts on its start time.
  def weekdays
    return [] unless weekly? && start_time

    days = Array(repeat_days) | [ local_start.strftime("%A").downcase ]
    WEEKDAYS.select { |day| days.include?(day) }
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

  # Without UNTIL. A weekly rule starts its weeks on Sunday, as Outlook does,
  # so a rule for every other week picks the same days in each provider. A
  # monthly meeting repeats on the same weekday of the month, for example the
  # second Wednesday.
  def recurrence_rule
    case frequency
    when "daily"
      IceCube::Rule.daily(repeat_interval)
    when "weekly"
      IceCube::Rule.weekly(repeat_interval, :sunday).day(*weekdays.map(&:to_sym))
    when "monthly"
      week = MONTHLY_WEEKS.fetch(((local_start.day - 1) / 7) + 1)
      IceCube::Rule.monthly(repeat_interval).day_of_week(local_start.strftime("%A").downcase.to_sym => [ week ])
    end
  end

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
    if repeat_until < local_start.to_date
      errors.add(:repeat_until, "must be on or after the start date")
    elsif repeat_until > local_start.to_date + MAX_REPEAT_LENGTH
      errors.add(:repeat_until, "must be no more than #{MAX_REPEAT_LENGTH.in_days.to_i} days after the start date")
    end
  end

  def repeat_days_are_weekdays
    return if repeat_days.blank?

    if !weekly?
      errors.add(:repeat_days, "can be set only for a weekly meeting")
    elsif (repeat_days - WEEKDAYS).any?
      errors.add(:repeat_days, "must list only #{WEEKDAYS.join(', ')}")
    end
  end
end

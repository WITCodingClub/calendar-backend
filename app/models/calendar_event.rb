# frozen_string_literal: true

# == Schema Information
#
# Table name: calendar_events
#
#  id                           :bigint           not null, primary key
#  end_time                     :datetime
#  event_data_hash              :string
#  external_ical_uid            :string
#  last_synced_at               :datetime
#  location                     :string
#  recurrence                   :text
#  start_time                   :datetime
#  summary                      :string
#  user_edited_fields           :jsonb
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  calendar_id                  :bigint           not null
#  external_event_id            :string           not null
#  final_exam_id                :bigint
#  friend_meeting_id            :bigint
#  meeting_time_id              :bigint
#  university_calendar_event_id :bigint
#
# Indexes
#
#  idx_calendar_events_on_calendar_id_meeting_time_id     (calendar_id,meeting_time_id)
#  idx_calendar_events_unique_final_exam                  (calendar_id,final_exam_id) UNIQUE WHERE (final_exam_id IS NOT NULL)
#  idx_calendar_events_unique_friend_meeting              (calendar_id,friend_meeting_id) UNIQUE WHERE (friend_meeting_id IS NOT NULL)
#  idx_calendar_events_unique_meeting_time                (calendar_id,meeting_time_id) UNIQUE WHERE (meeting_time_id IS NOT NULL)
#  idx_calendar_events_unique_university                  (calendar_id,university_calendar_event_id) UNIQUE WHERE (university_calendar_event_id IS NOT NULL)
#  index_calendar_events_on_external_event_id             (external_event_id)
#  index_calendar_events_on_external_ical_uid             (external_ical_uid)
#  index_calendar_events_on_final_exam_id                 (final_exam_id)
#  index_calendar_events_on_friend_meeting_id             (friend_meeting_id)
#  index_calendar_events_on_last_synced_at                (last_synced_at)
#  index_calendar_events_on_meeting_time_id               (meeting_time_id)
#  index_calendar_events_on_university_calendar_event_id  (university_calendar_event_id)
#
# Foreign Keys
#
#  fk_rails_...  (calendar_id => calendars.id)
#  fk_rails_...  (final_exam_id => final_exams.id) ON DELETE => nullify
#  fk_rails_...  (friend_meeting_id => friend_meetings.id)
#  fk_rails_...  (meeting_time_id => course_meeting_times.id)
#  fk_rails_...  (university_calendar_event_id => university_calendar_events.id) ON DELETE => nullify
#
class CalendarEvent < ApplicationRecord
  include EncodedIds::HashidIdentifiable

  set_public_id_prefix :gce, min_hash_length: 12

  belongs_to :course_calendar, foreign_key: :calendar_id, inverse_of: :calendar_events
  belongs_to :meeting_time, class_name: "Course::MeetingTime", optional: true
  belongs_to :final_exam, optional: true
  belongs_to :university_calendar_event, optional: true
  belongs_to :friend_meeting, optional: true
  has_one :event_preference, as: :preferenceable, dependent: :destroy
  has_one :oauth_credential, through: :course_calendar
  has_one :user, through: :oauth_credential

  validates :external_event_id, presence: true
  validate :only_one_event_type_associated
  validates :meeting_time_id, uniqueness: { scope: :calendar_id }, if: :meeting_time_id?
  validates :final_exam_id, uniqueness: { scope: :calendar_id }, if: :final_exam?
  validates :university_calendar_event_id, uniqueness: { scope: :calendar_id }, if: :university_event?
  validates :friend_meeting_id, uniqueness: { scope: :calendar_id }, if: :friend_meeting?

  serialize :recurrence, coder: JSON

  # Set by the sync service when it has already deleted the remote event itself,
  # so destroying the DB row doesn't enqueue a redundant deletion.
  attr_accessor :skip_remote_deletion

  before_destroy :capture_remote_event_ref
  after_commit :enqueue_remote_event_deletion, on: :destroy

  scope :university_events_only, -> { where.not(university_calendar_event_id: nil) }
  scope :orphaned,               -> { where(meeting_time_id: nil, final_exam_id: nil, university_calendar_event_id: nil, friend_meeting_id: nil) }
  # The rows that a course sync owns. A friend meeting row is not part of the
  # schedule, so the sync must never reconcile it away.
  scope :schedule_events,        -> { where(friend_meeting_id: nil) }
  scope :friend_meetings_only,   -> { where.not(friend_meeting_id: nil) }

  def final_exam?       = final_exam_id.present?
  def university_event? = university_calendar_event_id.present?
  def friend_meeting?   = friend_meeting_id.present?

  # The record each tracking column points at. A row has exactly one.
  SOURCE_COLUMNS = {
    "Course::MeetingTime"     => :meeting_time_id,
    "FinalExam"               => :final_exam_id,
    "UniversityCalendarEvent" => :university_calendar_event_id,
    "FriendMeeting"           => :friend_meeting_id
  }.freeze

  def self.source_column(record) = SOURCE_COLUMNS.fetch(record.class.name)

  # The column that tracks the row's source and the source id, as
  # CourseCalendars::Event#source_key gives it.
  def source_key
    column = SOURCE_COLUMNS.values.find { |name| self[name] }
    [ column, self[column] ] if column
  end

  def data_changed?(event)
    event_data_hash != event.data_hash
  end

  def mark_synced!
    update_columns(last_synced_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  private

  # Records the remote event before the row is destroyed so we can delete the
  # live provider event after the transaction commits. Skipped when the
  # sync service already handled the remote delete, or when the whole calendar is
  # being torn down (delete_calendar cleans up its events server-side). A
  # primary calendar is never deleted, so its events are deleted one by one.
  # A Microsoft friend meeting is always in the primary calendar, so it too
  # is deleted on its own.
  def capture_remote_event_ref
    return if skip_remote_deletion
    return if destroyed_by_association&.foreign_key.to_s == "calendar_id" && !in_primary_calendar?

    calendar = course_calendar
    @remote_event_ref = {
      provider:            calendar&.provider,
      calendar_id:         calendar&.external_calendar_id,
      oauth_credential_id: calendar&.oauth_credential_id,
      event_id:            external_event_id,
      ical_uid:            external_ical_uid
    }
  end

  def in_primary_calendar?
    calendar = course_calendar
    return false unless calendar

    calendar.primary_placement? || (calendar.microsoft? && friend_meeting?)
  end

  def enqueue_remote_event_deletion
    return if @remote_event_ref.blank?

    ref = @remote_event_ref
    return if ref[:calendar_id].blank? || ref[:event_id].blank?

    CourseCalendars::Providers.for(ref[:provider]).delete_event_later(ref)
  end

  def only_one_event_type_associated
    return if SOURCE_COLUMNS.values.count { |column| self[column] } == 1

    errors.add(:base, "Must be associated with exactly one of: meeting_time, final_exam, university_calendar_event, or friend_meeting")
  end
end

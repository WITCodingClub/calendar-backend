# frozen_string_literal: true

# == Schema Information
#
# Table name: google_calendar_events
# Database name: primary
#
#  id                           :bigint           not null, primary key
#  end_time                     :datetime
#  event_data_hash              :string
#  last_synced_at               :datetime
#  location                     :string
#  recurrence                   :text
#  start_time                   :datetime
#  summary                      :string
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  final_exam_id                :bigint
#  google_calendar_id           :bigint           not null
#  google_event_id              :string           not null
#  meeting_time_id              :bigint
#  university_calendar_event_id :bigint
#
# Indexes
#
#  idx_gcal_events_on_calendar_and_uni_event                     (google_calendar_id,university_calendar_event_id)
#  idx_gcal_events_unique_final_exam                             (google_calendar_id,final_exam_id) UNIQUE WHERE (final_exam_id IS NOT NULL)
#  idx_gcal_events_unique_meeting_time                           (google_calendar_id,meeting_time_id) UNIQUE WHERE (meeting_time_id IS NOT NULL)
#  idx_gcal_events_unique_university                             (google_calendar_id,university_calendar_event_id) UNIQUE WHERE (university_calendar_event_id IS NOT NULL)
#  idx_on_google_calendar_id_meeting_time_id_6c9efabf50          (google_calendar_id,meeting_time_id)
#  index_google_calendar_events_on_final_exam_id                 (final_exam_id)
#  index_google_calendar_events_on_google_calendar_id            (google_calendar_id)
#  index_google_calendar_events_on_google_event_id               (google_event_id)
#  index_google_calendar_events_on_last_synced_at                (last_synced_at)
#  index_google_calendar_events_on_meeting_time_id               (meeting_time_id)
#  index_google_calendar_events_on_university_calendar_event_id  (university_calendar_event_id)
#
# Foreign Keys
#
#  fk_rails_...  (final_exam_id => final_exams.id)
#  fk_rails_...  (google_calendar_id => google_calendars.id)
#  fk_rails_...  (meeting_time_id => meeting_times.id)
#  fk_rails_...  (university_calendar_event_id => university_calendar_events.id)
#
class GoogleCalendarEvent < ApplicationRecord
  include PublicIdentifiable

  set_public_id_prefix :gce, min_hash_length: 12

  belongs_to :google_calendar
  belongs_to :meeting_time, optional: true
  belongs_to :final_exam, optional: true
  belongs_to :university_calendar_event, optional: true
  has_one :event_preference, as: :preferenceable, dependent: :destroy
  has_one :oauth_credential, through: :google_calendar
  has_one :user, through: :oauth_credential

  validates :google_event_id, presence: true

  # Ensure only one type of event is associated
  validate :only_one_event_type_associated

  # Ensure no duplicates for the same calendar and event
  validates :meeting_time_id, uniqueness: { scope: :google_calendar_id }, if: :meeting_time_id?
  validates :final_exam_id, uniqueness: { scope: :google_calendar_id }, if: :final_exam?
  validates :university_calendar_event_id, uniqueness: { scope: :google_calendar_id }, if: :university_event?

  # Serialize recurrence as an array
  serialize :recurrence, coder: JSON

  scope :for_user, ->(user) { where(user: user) }
  scope :for_calendar, ->(calendar) { where(google_calendar: calendar) }
  scope :for_meeting_time, ->(meeting_time_id) { where(meeting_time_id: meeting_time_id) }
  scope :for_final_exam, ->(final_exam_id) { where(final_exam_id: final_exam_id) }
  scope :stale, ->(time_ago = 1.hour) { where("last_synced_at IS NULL OR last_synced_at < ?", time_ago.ago) }
  scope :recently_synced, -> { where("last_synced_at > ?", 5.minutes.ago) }
  scope :finals_only, -> { where.not(final_exam_id: nil) }
  scope :courses_only, -> { where.not(meeting_time_id: nil) }
  scope :university_events_only, -> { where.not(university_calendar_event_id: nil) }
  scope :for_university_calendar_event, ->(event_id) { where(university_calendar_event_id: event_id) }

  # Returns true if this event is for a final exam
  def final_exam?
    final_exam_id.present?
  end

  # Returns true if this event is for a regular class meeting
  def meeting_time?
    meeting_time_id.present?
  end

  # Returns true if this event is for a university calendar event
  def university_event?
    university_calendar_event_id.present?
  end

  # Get the syncable record (meeting_time, final_exam, or university_calendar_event)
  def syncable
    meeting_time || final_exam || university_calendar_event
  end

  # Generate a hash of the event data to detect changes
  # Includes all preference-controlled fields to ensure events update when preferences change
  def self.generate_data_hash(event_data)
    hash_input = [
      event_data[:summary],
      event_data[:location],
      event_data[:start_time]&.to_i,
      event_data[:end_time]&.to_i,
      event_data[:recurrence]&.to_json,
      event_data[:reminder_settings]&.to_json,
      event_data[:color_id]&.to_s,
      event_data[:visibility],
      event_data[:all_day]
    ].join("|")

    Digest::SHA256.hexdigest(hash_input)
  end

  # Check if this event's data has changed
  def data_changed?(new_event_data)
    new_hash = self.class.generate_data_hash(new_event_data)
    event_data_hash != new_hash
  end

  # Update the event data hash
  def update_data_hash!(event_data)
    update_column(:event_data_hash, self.class.generate_data_hash(event_data)) # rubocop:disable Rails/SkipsModelValidations
  end

  # Mark as synced
  def mark_synced!
    update_columns(last_synced_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  # Check if event needs syncing based on staleness
  def needs_sync?(threshold = 1.hour)
    last_synced_at.nil? || last_synced_at < threshold.ago
  end

  private

  # Ensure only one event type is associated at a time
  def only_one_event_type_associated
    event_types = [meeting_time_id, final_exam_id, university_calendar_event_id].compact
    return unless event_types.size != 1

    errors.add(:base, "Must be associated with exactly one of: meeting_time, final_exam, or university_calendar_event")

  end

end

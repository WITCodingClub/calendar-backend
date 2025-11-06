# frozen_string_literal: true

# == Schema Information
#
# Table name: google_calendar_events
# Database name: primary
#
#  id                 :bigint           not null, primary key
#  end_time           :datetime
#  event_data_hash    :string
#  last_synced_at     :datetime
#  location           :string
#  recurrence         :text
#  start_time         :datetime
#  summary            :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  google_calendar_id :bigint           not null
#  google_event_id    :string           not null
#  meeting_time_id    :bigint
#  user_id            :bigint           not null
#
# Indexes
#
#  index_google_calendar_events_on_google_calendar_id               (google_calendar_id)
#  index_google_calendar_events_on_google_calendar_id_and_meeting_  (google_calendar_id,meeting_time_id)
#  index_google_calendar_events_on_google_event_id                  (google_event_id)
#  index_google_calendar_events_on_meeting_time_id                  (meeting_time_id)
#  index_google_calendar_events_on_user_id                          (user_id)
#  index_google_calendar_events_on_user_id_and_meeting_time_id      (user_id,meeting_time_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (meeting_time_id => meeting_times.id)
#  fk_rails_...  (user_id => users.id)
#
class GoogleCalendarEvent < ApplicationRecord
  belongs_to :user
  belongs_to :google_calendar
  belongs_to :meeting_time, optional: true
  has_one :event_preference, as: :preferenceable, dependent: :destroy

  validates :google_event_id, presence: true
  validates :user_id, uniqueness: { scope: :meeting_time_id }, if: :meeting_time_id?

  # Serialize recurrence as an array
  serialize :recurrence, coder: JSON

  scope :for_user, ->(user) { where(user: user) }
  scope :for_calendar, ->(calendar) { where(google_calendar: calendar) }
  scope :for_meeting_time, ->(meeting_time_id) { where(meeting_time_id: meeting_time_id) }
  scope :stale, ->(time_ago = 1.hour) { where("last_synced_at IS NULL OR last_synced_at < ?", time_ago.ago) }
  scope :recently_synced, -> { where("last_synced_at > ?", 5.minutes.ago) }

  # Generate a hash of the event data to detect changes
  def self.generate_data_hash(event_data)
    hash_input = [
      event_data[:summary],
      event_data[:location],
      event_data[:start_time]&.to_i,
      event_data[:end_time]&.to_i,
      event_data[:recurrence]&.to_json
    ].join("|")

    Digest::SHA256.hexdigest(hash_input)[0..15] # Use first 16 chars
  end

  # Check if this event's data has changed
  def data_changed?(new_event_data)
    new_hash = self.class.generate_data_hash(new_event_data)
    event_data_hash != new_hash
  end

  # Update the event data hash
  def update_data_hash!(event_data)
    update_column(:event_data_hash, self.class.generate_data_hash(event_data))
  end

  # Mark as synced
  def mark_synced!
    update_columns(last_synced_at: Time.current)
  end

  # Check if event needs syncing based on staleness
  def needs_sync?(threshold = 1.hour)
    last_synced_at.nil? || last_synced_at < threshold.ago
  end

end

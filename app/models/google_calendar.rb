# frozen_string_literal: true

# == Schema Information
#
# Table name: google_calendars
# Database name: primary
#
#  id                  :bigint           not null, primary key
#  description         :text
#  last_synced_at      :datetime
#  summary             :string
#  time_zone           :string
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  google_calendar_id  :string           not null
#  oauth_credential_id :bigint           not null
#
# Indexes
#
#  index_google_calendars_on_google_calendar_id   (google_calendar_id) UNIQUE
#  index_google_calendars_on_last_synced_at       (last_synced_at)
#  index_google_calendars_on_oauth_credential_id  (oauth_credential_id)
#
# Foreign Keys
#
#  fk_rails_...  (oauth_credential_id => oauth_credentials.id)
#
class GoogleCalendar < ApplicationRecord
  belongs_to :oauth_credential
  has_many :google_calendar_events, dependent: :destroy
  has_one :user, through: :oauth_credential

  validates :google_calendar_id, presence: true, uniqueness: true

  scope :for_user, ->(user) { joins(:oauth_credential).where(oauth_credentials: { user_id: user.id }) }
  scope :stale, ->(time_ago = 1.hour) { where("last_synced_at IS NULL OR last_synced_at < ?", time_ago.ago) }

  # Mark calendar as synced
  def mark_synced!
    update_columns(last_synced_at: Time.current)
  end

  # Check if calendar needs syncing based on staleness
  def needs_sync?(threshold = 1.hour)
    last_synced_at.nil? || last_synced_at < threshold.ago
  end

end

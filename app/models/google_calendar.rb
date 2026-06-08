# frozen_string_literal: true

class GoogleCalendar < ApplicationRecord
  include EncodedIds::HashidIdentifiable

  set_public_id_prefix :gcl

  belongs_to :oauth_credential
  has_many :google_calendar_events, dependent: :destroy
  has_one :user, through: :oauth_credential

  validates :google_calendar_id, presence: true, uniqueness: true

  before_destroy :enqueue_google_calendar_deletion

  scope :for_user, ->(user) { joins(:oauth_credential).where(oauth_credentials: { user_id: user.id }) }
  scope :stale, ->(time_ago = 1.hour) { where("last_synced_at IS NULL OR last_synced_at < ?", time_ago.ago) }

  def mark_synced!
    update_columns(last_synced_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  def needs_sync?(threshold = 1.hour)
    last_synced_at.nil? || last_synced_at < threshold.ago
  end

  private

  def enqueue_google_calendar_deletion
    return if google_calendar_id.blank?

    GoogleCalendarDeleteJob.perform_later(google_calendar_id)
  rescue => e
    Rails.logger.error("Failed to enqueue GoogleCalendarDeleteJob for #{google_calendar_id}: #{e.message}")
  end
end

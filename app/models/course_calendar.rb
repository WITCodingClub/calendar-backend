# frozen_string_literal: true

# == Schema Information
#
# Table name: calendars
#
#  id                   :bigint           not null, primary key
#  description          :text
#  last_synced_at       :datetime
#  provider             :string           default("google"), not null
#  summary              :string
#  time_zone            :string
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  external_calendar_id :string           not null
#  oauth_credential_id  :bigint           not null
#
# Indexes
#
#  index_calendars_on_last_synced_at                        (last_synced_at)
#  index_calendars_on_oauth_credential_id_unique            (oauth_credential_id) UNIQUE
#  index_calendars_on_provider_and_external_calendar_id     (provider,external_calendar_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (oauth_credential_id => oauth_credentials.id)
#
# The course calendar that one OAuth credential syncs to, at one provider.
#
# The class is not named Calendar because the application module is Calendar
# (config/application.rb), so that constant is taken.
class CourseCalendar < ApplicationRecord
  include EncodedIds::HashidIdentifiable

  self.table_name = "calendars"

  # The prefix stays "gcl" so public ids issued before the rename still resolve.
  set_public_id_prefix :gcl

  PROVIDERS = { google: "google", microsoft: "microsoft" }.freeze

  enum :provider, PROVIDERS, validate: true

  belongs_to :oauth_credential
  has_many :calendar_events, foreign_key: :calendar_id, inverse_of: :course_calendar, dependent: :destroy
  has_one :user, through: :oauth_credential

  validates :external_calendar_id, presence: true, uniqueness: { scope: :provider }
  # One course calendar per OAuth credential — the app treats this as a has_one.
  validates :oauth_credential_id, uniqueness: true

  before_destroy :enqueue_remote_calendar_deletion

  # Set when the remote calendar was already deleted, or cannot be deleted
  # later, so destroying the row does not enqueue a delete job.
  attr_accessor :skip_remote_deletion

  scope :for_user, ->(user) { joins(:oauth_credential).where(oauth_credentials: { user_id: user.id }) }
  scope :stale, ->(time_ago = 1.hour) { where("last_synced_at IS NULL OR last_synced_at < ?", time_ago.ago) }

  def mark_synced!
    update_columns(last_synced_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  def needs_sync?(threshold = 1.hour)
    last_synced_at.nil? || last_synced_at < threshold.ago
  end

  private

  def enqueue_remote_calendar_deletion
    return if skip_remote_deletion || external_calendar_id.blank?

    if microsoft?
      MicrosoftGraphCalendarDeleteJob.perform_later(oauth_credential_id, external_calendar_id)
    else
      GoogleCalendarDeleteJob.perform_later(external_calendar_id)
    end
  rescue => e
    Rails.logger.error("Failed to enqueue calendar deletion for #{external_calendar_id}: #{e.message}")
  end
end

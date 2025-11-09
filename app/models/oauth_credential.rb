# frozen_string_literal: true

# == Schema Information
#
# Table name: oauth_credentials
# Database name: primary
#
#  id               :bigint           not null, primary key
#  access_token     :string           not null
#  email            :string
#  metadata         :jsonb
#  provider         :string           not null
#  refresh_token    :string
#  token_expires_at :datetime
#  uid              :string           not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  user_id          :bigint           not null
#
# Indexes
#
#  index_oauth_credentials_on_provider_and_uid     (provider,uid) UNIQUE
#  index_oauth_credentials_on_user_id              (user_id)
#  index_oauth_credentials_on_user_provider_email  (user_id,provider,email) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class OauthCredential < ApplicationRecord
  belongs_to :user
  has_one :google_calendar, dependent: :destroy

  validates :provider, presence: true, inclusion: { in: %w[google] }
  validates :uid, presence: true, uniqueness: { scope: :provider }
  validates :access_token, presence: true
  validates :email, presence: true, format: { with: /\A[^@\s]+@[^@\s]+\z/, message: "must be a valid email address" }

  encrypts :access_token
  encrypts :refresh_token

  # Revoke calendar access before destroying the OAuth credential
  before_destroy :revoke_calendar_access

  # Get the course calendar ID from the associated GoogleCalendar record
  def course_calendar_id
    google_calendar&.google_calendar_id
  end

  # Legacy setter - no longer needed since we use GoogleCalendar association
  # But kept for backward compatibility in case anything still calls it
  def course_calendar_id=(value)
    # This is a no-op now - the calendar ID is managed by the GoogleCalendar record
    Rails.logger.warn("OauthCredential#course_calendar_id= is deprecated. Use GoogleCalendar association instead.")
  end

  # Check if token is expired or about to expire (within 5 minutes)
  def token_expired?
    token_expires_at.nil? || token_expires_at <= 5.minutes.from_now
  end

  # Scope for finding credentials by provider
  scope :for_provider, ->(provider) { where(provider: provider) }
  scope :google, -> { for_provider("google") }

  private

  def revoke_calendar_access
    return if google_calendar&.google_calendar_id.blank?

    begin
      # Remove the email's access to the Google Calendar
      service = GoogleCalendarService.new(user)
      service.unshare_calendar_with_email(google_calendar.google_calendar_id, email)

      Rails.logger.info("Revoked calendar access for #{email} from calendar #{google_calendar.google_calendar_id}")
    rescue => e
      # Log but don't prevent deletion if calendar access revocation fails
      Rails.logger.error("Failed to revoke calendar access for #{email}: #{e.message}")
    end
  end

end

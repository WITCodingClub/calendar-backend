# frozen_string_literal: true

class OauthCredential < ApplicationRecord
  include EncodedIds::HashidIdentifiable

  set_public_id_prefix :oac

  belongs_to :user
  has_one :google_calendar, dependent: :destroy
  has_many :security_events, dependent: :nullify

  validates :provider, presence: true, inclusion: { in: %w[google] }
  validates :uid, presence: true, uniqueness: { scope: :provider }
  validates :access_token, presence: true
  validates :email, presence: true, format: { with: /\A[^@\s]+@[^@\s]+\z/, message: "must be a valid email address" }

  before_destroy :revoke_calendar_access

  scope :for_provider, ->(provider) { where(provider: provider) }
  scope :google,        -> { for_provider("google") }
  scope :revoked,       -> { where("metadata->>'token_revoked' = 'true'") }
  scope :needs_refresh, -> { where(updated_at: ...7.days.ago).where.not(refresh_token: nil) }

  def course_calendar_id
    google_calendar&.google_calendar_id
  end

  def token_expired?
    token_expires_at.nil? || token_expires_at <= 5.minutes.from_now
  end

  def token_revoked?
    metadata&.dig("token_revoked") == true
  end

  def needs_reauth?
    token_revoked? || refresh_token.blank?
  end

  private

  def revoke_calendar_access
    return if google_calendar&.google_calendar_id.blank?

    service = GoogleCalendarService.new(user)
    service.unshare_calendar_with_email(google_calendar.google_calendar_id, email)
  rescue => e
    Rails.logger.error("Failed to revoke calendar access for #{email}: #{e.message}")
  end
end

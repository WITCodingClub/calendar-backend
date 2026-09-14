# frozen_string_literal: true

# == Schema Information
#
# Table name: oauth_credentials
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
#  index_oauth_credentials_on_token_expires_at     (token_expires_at)
#  index_oauth_credentials_on_user_id              (user_id)
#  index_oauth_credentials_on_user_provider_email  (user_id,provider,email) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class OauthCredential < ApplicationRecord
  include EncodedIds::HashidIdentifiable

  set_public_id_prefix :oac

  belongs_to :user
  has_one :course_calendar, dependent: :destroy
  has_many :security_events, dependent: :nullify

  # A Microsoft calendar lives in the person's mailbox, and only this
  # credential's token can delete it. `has_one :course_calendar, dependent:
  # :destroy` runs before any before_destroy declared after it, and the
  # MicrosoftGraphCalendarDeleteJob it enqueues runs after the credential is
  # gone. So this callback is prepended and deletes the calendar now.
  before_destroy :delete_microsoft_calendar, prepend: true, if: :microsoft?

  # Disconnecting the Google account that vouched for this person should not
  # leave tokens it produced still working. A Microsoft credential only syncs a
  # calendar and never signs anyone in, so removing it keeps the sessions.
  after_destroy :revoke_sessions, if: :google?

  PROVIDERS = %w[google microsoft].freeze

  validates :provider, presence: true, inclusion: { in: PROVIDERS }
  validates :uid, presence: true, uniqueness: { scope: :provider }
  validates :access_token, presence: true
  validates :email, presence: true, format: { with: /\A[^@\s]+@[^@\s]+\z/, message: "must be a valid email address" }

  before_destroy :revoke_calendar_access

  scope :for_provider, ->(provider) { where(provider: provider) }
  scope :google,        -> { for_provider("google") }
  scope :microsoft,     -> { for_provider("microsoft") }
  scope :revoked,       -> { where("metadata->>'token_revoked' = 'true'") }
  scope :needs_refresh, -> { where(updated_at: ...7.days.ago).where.not(refresh_token: nil) }

  def course_calendar_id
    course_calendar&.external_calendar_id
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

  def google?
    provider == "google"
  end

  def microsoft?
    provider == "microsoft"
  end

  # A Graph failure must not block the disconnect, so it is logged only.
  def delete_microsoft_calendar
    calendar = course_calendar
    return if calendar.nil? || calendar.external_calendar_id.blank?

    MicrosoftGraphCalendarService.new(user, credential: self).delete_calendar(calendar.external_calendar_id)
  rescue => e
    Rails.logger.error({ message: "Could not delete the Outlook calendar on disconnect",
                         oauth_credential_id: id, error: e.class.name }.to_json)
  ensure
    # The delete job would find no credential, so it is not enqueued.
    calendar&.skip_remote_deletion = true
  end

  # Only Google calendars are shared into the person's calendar list. A
  # Microsoft calendar lives in the person's own mailbox, so there is nothing
  # to unshare.
  def revoke_calendar_access
    return unless google?
    return if course_calendar&.external_calendar_id.blank?

    service = GoogleCalendarService.new(user)
    service.remove_calendar_from_user_list_for_email(course_calendar.external_calendar_id, email)
  rescue => e
    Rails.logger.error("Failed to revoke calendar access for #{email}: #{e.message}")
  end

  private

  def revoke_sessions
    UserSession.revoke_all_for(user, reason: "google account disconnected") if user
  end
end

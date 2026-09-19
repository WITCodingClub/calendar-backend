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

  # prepend: the dependent destroy above is a before_destroy callback too, and
  # it deletes the calendar row that the removal has to look up.
  before_destroy :revoke_calendar_access, prepend: true

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

  # Every way to disconnect an account (API, dashboard, admin, RISC, deleting
  # the user) ends the Google grant too. After commit, so a rolled back destroy
  # keeps its grant, and in a job, so the request does not wait for Google.
  # Google only: Google's revoke endpoint cannot end a Microsoft grant.
  after_destroy_commit :enqueue_google_token_revocation, if: :google?

  PROVIDERS = %w[google microsoft].freeze

  validates :provider, presence: true, inclusion: { in: PROVIDERS }
  validates :uid, presence: true, uniqueness: { scope: :provider }
  validates :access_token, presence: true
  validates :email, presence: true, format: { with: /\A[^@\s]+@[^@\s]+\z/, message: "must be a valid email address" }

  # RefreshOauthTokensJob flags a grant that Google refused. A new access token
  # only comes from a working grant, so saving one takes the flag away.
  before_update :clear_revoked_flag, if: :will_save_change_to_access_token?

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

  # A Graph failure must not block the disconnect, so it is logged only. When
  # the events are in the person's primary calendar, only the events go.
  def delete_microsoft_calendar
    calendar = course_calendar
    return if calendar.nil? || calendar.external_calendar_id.blank?

    MicrosoftGraphCalendarService.new(user, credential: self).remove_course_events(calendar)
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
  #
  # The course calendar belongs to one credential, but it is shared with every
  # Google account the person connects. So look it up for the user, not only
  # on this credential.
  def revoke_calendar_access
    return unless google?

    calendar_id = CourseCalendar.google.for_user(user).pick(:external_calendar_id) if user
    return if calendar_id.blank?

    service = GoogleCalendarService.new(user)
    report_google_failure("remove the course calendar from the calendar list") do
      service.remove_calendar_from_user_list_for_email(calendar_id, email)
    end
    report_google_failure("stop sharing the course calendar") do
      service.unshare_calendar_with_email(calendar_id, email)
    end
  end

  # Google can refuse or be down, and that must not block the disconnect. Any
  # other error is a bug, so it is not rescued here.
  def report_google_failure(action)
    yield
  rescue Google::Apis::Error, Signet::AuthorizationError, Signet::RemoteServerError,
         Signet::UnexpectedStatusError, Faraday::Error => e
    Rails.logger.error("Failed to #{action} for #{email}: #{e.message}")
    Rails.error.report(e, handled: true, context: { oauth_credential_id: id, action: action })
  end

  # The refresh token ends the whole grant. Google does not revoke an access
  # token that has expired.
  def enqueue_google_token_revocation
    RevokeGoogleTokenJob.perform_later(refresh_token.presence || access_token)
  end

  def clear_revoked_flag
    return unless token_revoked?

    self.metadata = metadata.except("token_revoked", "token_revoked_at", "revocation_reason")
  end

  # Sessions do not record a credential. Onboarding opens google_onboard
  # sessions only after Google verifies the user's own WIT email, so that
  # account is the one that vouched for them. Any other Google account only
  # shares the calendar, and passkey sessions end with their passkey.
  def revoke_sessions
    return unless user && email.to_s.casecmp?(user.email.to_s)

    UserSession.revoke_all_for(user, reason: "google account disconnected", source: "google_onboard")
  end
end

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
#  index_oauth_credentials_on_user_provider_email  (user_id,provider,email) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class OauthCredential < ApplicationRecord
  include EncodedIds::HashidIdentifiable

  set_public_id_prefix :oac

  # Blazer gives admins SQL access, so the tokens are stored as ciphertext.
  # Non-deterministic: no code looks a credential up by its token value. A
  # plain-text row raises on read. Production encrypted its old plain-text rows
  # on 2026-10-09 (#713).
  encrypts :access_token, :refresh_token

  belongs_to :user
  has_one :course_calendar, dependent: :destroy
  has_many :security_events, dependent: :nullify

  # prepend: the dependent destroy above is a before_destroy callback too, and
  # it deletes the calendar row that the provider still needs.
  before_destroy :release_calendar, prepend: true

  # Disconnecting the Google account that vouched for this person should not
  # leave tokens it produced still working. A Microsoft credential only syncs a
  # calendar and never signs anyone in, so removing it keeps the sessions.
  after_destroy :revoke_sessions, if: :google?

  # Every way to disconnect an account (API, dashboard, admin, RISC, deleting
  # the user) ends the grant too, where the provider can. After commit, so a
  # rolled back destroy keeps its grant, and in a job, so the request does not
  # wait for the provider.
  after_destroy_commit :revoke_grant

  PROVIDERS = CourseCalendars::Providers::CLASSES.keys.freeze

  GOOGLE_CALENDAR_SCOPE = "https://www.googleapis.com/auth/calendar"

  # A token that ends within this time counts as expired, so it is refreshed
  # before a call and does not end in the middle of one.
  EXPIRY_MARGIN = 5.minutes

  # OauthCredentials::RefreshTokensJob refreshes each credential that has not
  # changed for this long. A Microsoft refresh token expires after 90 days
  # without use, so a weekly refresh keeps an idle connection alive.
  REFRESH_AFTER = 7.days

  validates :provider, presence: true, inclusion: { in: PROVIDERS }
  validates :uid, presence: true, uniqueness: { scope: :provider }
  validates :access_token, presence: true
  validates :email, presence: true, format: { with: /\A[^@\s]+@[^@\s]+\z/, message: "must be a valid email address" }

  # A provider refused the grant (mark_revoked!). A new access token only
  # comes from a working grant, so saving one takes the flag away.
  before_update :clear_revoked_flag, if: :will_save_change_to_access_token?
  # A new token can finish friend meeting work that a refused token stopped.
  after_commit :resume_friend_meetings, on: %i[create update], if: :saved_change_to_access_token?

  scope :for_provider, ->(provider) { where(provider: provider) }
  scope :google,        -> { for_provider("google") }
  scope :microsoft,     -> { for_provider("microsoft") }
  scope :revoked,       -> { where("metadata->>'token_revoked' = 'true'") }
  scope :needs_refresh, -> { where(updated_at: ...REFRESH_AFTER.ago).where.not(refresh_token: nil) }

  def token_expired?
    token_expires_at.nil? || token_expires_at <= EXPIRY_MARGIN.from_now
  end

  def token_revoked?
    metadata&.dig("token_revoked") == true
  end

  def needs_reauth?
    token_revoked? || refresh_token.blank?
  end

  # Flags a grant that the provider will not take again, so the dashboard
  # asks the person to sign in again.
  def mark_revoked!(reason)
    update!(metadata: (metadata || {}).merge(
      "token_revoked"     => true,
      "token_revoked_at"  => Time.current.iso8601,
      "revocation_reason" => reason
    ))
  end

  # Refreshes the access token with the provider and saves it.
  def refresh!
    calendar_provider.refresh_token!(self)
  end

  # The Google authorization for this credential. An expired token (or any
  # token, with refresh: true) is refreshed and saved first. When Google
  # answers invalid_grant, the person revoked the grant or the refresh token
  # expired, so the credential is marked revoked. Other token errors, such as
  # invalid_client after a secret rotation, say nothing about the person.
  def google_authorization(refresh: false)
    authorization = Google::Auth::UserRefreshCredentials.new(
      client_id:     Rails.application.credentials.dig(:google, :client_id),
      client_secret: Rails.application.credentials.dig(:google, :client_secret),
      scope:         [ GOOGLE_CALENDAR_SCOPE ],
      access_token:  access_token,
      refresh_token: refresh_token,
      expires_at:    token_expires_at
    )
    return authorization unless refresh || token_expired?

    begin
      authorization.refresh!
    rescue Signet::AuthorizationError => e
      mark_revoked!(e.message) if e.message.match?(/"error"\s*:\s*"invalid_grant"/)
      raise
    end
    update!(access_token: authorization.access_token, token_expires_at: Time.zone.at(authorization.expires_at))
    authorization
  end

  # Whether the person can disconnect this credential.
  #
  # A Google credential carries the sign-in of the account and the only way
  # the app can reach a Google calendar, so the last one stays. A Microsoft
  # credential only syncs a calendar, and a person who connected Outlook alone
  # must be able to remove it.
  def removable?
    return true unless google?

    user.oauth_credentials.google.where.not(id: id).exists?
  end

  def google?
    provider == "google"
  end

  def microsoft?
    provider == "microsoft"
  end

  def calendar_provider
    CourseCalendars::Providers.for(provider)
  end

  private

  def release_calendar
    calendar_provider.release_calendar(self)
  end

  def revoke_grant
    calendar_provider.revoke_later(self)
  end

  # Most people have no friend meeting work waiting, so this costs two
  # indexed queries and starts no job.
  def resume_friend_meetings
    return unless user

    meetings = user.friend_meetings
    waiting  = meetings.where.not(cancelled_at: nil).exists? ||
               FriendMeetingPublication.where(friend_meeting_id: meetings.select(:id), status: %w[failed removed]).exists?
    FriendMeetings::ResumeJob.perform_later(user) if waiting
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

# frozen_string_literal: true

module GoogleSignIn
  # Saves the tokens of one Google account on one user.
  #
  # A Google account (provider + uid) belongs to at most one user. A user has at
  # most one Google credential per email. Both rules are unique indexes, so this
  # service checks them first and raises Conflict with a message for the person,
  # not a database error.
  class AccountLink
    class Conflict < StandardError; end

    OTHER_USER_MESSAGE = "That Google account is already connected to another user"
    PENDING_TTL        = 10.minutes

    # A link that waits for the person to confirm it. The tokens stay on the
    # server; the browser session holds only the random id.
    def self.store_pending(data)
      id = SecureRandom.urlsafe_base64(32)
      Rails.cache.write(pending_key(id), data, expires_in: PENDING_TTL)
      id
    end

    def self.read_pending(id)
      id.present? ? Rails.cache.read(pending_key(id)) : nil
    end

    def self.discard_pending(id)
      Rails.cache.delete(pending_key(id)) if id.present?
    end

    def self.pending_key(id)
      "google_pending_link:#{id}"
    end
    private_class_method :pending_key

    attr_reader :user

    def initialize(user)
      @user = user
    end

    # Raises Conflict when the account cannot be linked to this user.
    def check!(uid:, email:)
      credential_for(uid: uid, email: email)
      nil
    end

    # Saves the tokens and returns the credential.
    def link!(uid:, email:, access_token:, refresh_token: nil, expires_at: nil)
      credential = credential_for(uid: uid, email: email)
      credential.email            = email
      credential.uid              = uid
      credential.access_token     = access_token
      credential.refresh_token    = refresh_token if refresh_token.present?
      credential.token_expires_at = Time.zone.at(expires_at) if expires_at
      credential.save!
      credential
    rescue ActiveRecord::RecordNotUnique
      # A parallel request linked the same account first.
      raise Conflict, OTHER_USER_MESSAGE
    end

    # Links the account, makes sure the course calendar exists and starts a
    # sync. Returns the calendar id.
    def connect!(**tokens)
      link!(**tokens)

      calendar_id = GoogleCalendar::Provider.new(user).create_or_get_course_calendar
      CourseCalendars::SyncJob.perform_later(user, force: false) if user.enrollments.any?
      calendar_id
    end

    private

    def credential_for(uid:, email:)
      existing = OauthCredential.find_by(provider: "google", uid: uid)
      raise Conflict, OTHER_USER_MESSAGE if existing && existing.user_id != user.id

      credential = existing || user.oauth_credentials.find_or_initialize_by(provider: "google", email: email)

      # The account's email changed at Google, and the new email is already on
      # another credential of this user. Saving would break the unique email
      # index, so the person must disconnect that credential first.
      if credential.email != email && user.oauth_credentials.where(provider: "google", email: email).where.not(id: credential.id).exists?
        raise Conflict, "Another connected Google account already uses #{email}. Disconnect it, then try again."
      end

      credential
    end
  end
end

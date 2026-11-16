# frozen_string_literal: true

module OauthCredentials
  # Saves the tokens of one provider account on one user, and connects its
  # course calendar. Every calendar connection (Google, Microsoft) ends here.
  #
  # An account (provider + uid) belongs to at most one user. A user has at
  # most one credential per provider and email. Both rules are unique indexes,
  # so this service checks them first and raises Conflict with a message for
  # the person, not a database error.
  class AccountLink
    class Conflict < StandardError; end

    PENDING_TTL = 10.minutes

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

    attr_reader :user, :provider

    def initialize(user, provider)
      @user     = user
      @provider = provider.to_s
    end

    # Raises Conflict when the account cannot be linked to this user.
    def check!(uid:, email:)
      credential_for(uid: uid, email: email)
      nil
    end

    # Saves the tokens and returns the credential. expires_at is a Time or
    # epoch seconds. Saving a new access token clears a revoked flag
    # (OauthCredential).
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
      raise Conflict, other_user_message
    end

    # Links the account, makes sure the course calendar exists, and starts one
    # sync (CourseCalendars::Provider#ensure_course_calendar). `calendar`
    # holds the provider's calendar options, such as the Microsoft placement.
    # Returns the calendar id.
    def connect!(calendar: {}, **tokens)
      credential = link!(**tokens)
      CourseCalendars::Providers.for(provider).new(user, credential: credential)
                                .ensure_course_calendar(always_sync: true, **calendar)
    end

    private

    def other_user_message
      "That #{provider.titleize} account is already connected to another user"
    end

    def credential_for(uid:, email:)
      existing = OauthCredential.find_by(provider: provider, uid: uid)
      raise Conflict, other_user_message if existing && existing.user_id != user.id

      credential = existing || user.oauth_credentials.find_or_initialize_by(provider: provider, email: email)

      # The account's email changed at the provider, and the new email is
      # already on another credential of this user. Saving would break the
      # unique email index, so the person must disconnect that credential
      # first.
      if credential.email != email && user.oauth_credentials.where(provider: provider, email: email).where.not(id: credential.id).exists?
        raise Conflict, "Another connected #{provider.titleize} account already uses #{email}. Disconnect it, then try again."
      end

      credential
    end
  end
end

# frozen_string_literal: true

module MicrosoftSignIn
  # Turns a Microsoft sign-in (the OmniAuth auth hash from the entra_id
  # strategy) into a User. It follows the Google dashboard sign-in rules: only
  # @wit.edu addresses, and the first sign-in creates the account.
  #
  # Linking rule:
  #
  # 1. The token must come from the configured WIT tenant (tid).
  # 2. The email must be a @wit.edu address.
  # 3. An identity with the same tid and oid signs in its user. The email is
  #    not used for this lookup, because it can change.
  # 4. With no identity, the email decides the account, like Google. The email
  #    is trusted only for a member of the WIT tenant. WIT owns the wit.edu
  #    domain in that tenant. A guest account (the idp claim names another
  #    identity provider) is refused and never linked, because its email comes
  #    from outside WIT.
  class Authenticator
    Result = Data.define(:user, :error) do
      def success? = error.nil?
    end

    WRONG_ACCOUNT = "Sign in with your WIT Microsoft account."

    def self.call(auth)
      new(auth).call
    end

    def initialize(auth)
      @auth   = auth
      @claims = auth.extra&.raw_info.to_h
    end

    def call
      return failure(WRONG_ACCOUNT) unless from_wit_tenant?

      unless User.wit_email?(email)
        return failure("Only @#{User::WIT_EMAIL_DOMAIN} email addresses are allowed.")
      end

      identity = SignInIdentity.microsoft.find_by(tenant_id: tenant_id, uid: object_id_claim)

      if identity
        identity.record_sign_in!(email: email)
        return success(identity.user)
      end

      return failure(WRONG_ACCOUNT) if guest?

      success(link_account)
    end

    private

    attr_reader :auth, :claims

    def link_account
      ActiveRecord::Base.transaction do
        user = User.find_or_provision_for_sign_in!(
          email:      email,
          first_name: auth.info&.first_name,
          last_name:  auth.info&.last_name
        )

        user.sign_in_identities.create!(
          provider:          PROVIDER,
          tenant_id:         tenant_id,
          uid:               object_id_claim,
          email:             email,
          last_signed_in_at: Time.current
        )

        user
      end
    end

    def from_wit_tenant?
      tenant_id.present? &&
        object_id_claim.present? &&
        tenant_id.casecmp?(MicrosoftSignIn.config[:tenant_id])
    end

    # The idp claim is absent, or the same as the issuer, for an account that
    # the tenant itself holds. A guest carries the identity provider of its
    # home tenant or of a personal Microsoft account.
    def guest?
      idp = claims["idp"].to_s
      idp.present? && !idp.downcase.include?(tenant_id.downcase)
    end

    def tenant_id
      claims["tid"].to_s
    end

    def object_id_claim
      claims["oid"].to_s
    end

    def email
      @email ||= (auth.info&.email.presence || claims["preferred_username"]).to_s.strip.downcase
    end

    def success(user)
      Result.new(user: user, error: nil)
    end

    def failure(message)
      Result.new(user: nil, error: message)
    end
  end
end

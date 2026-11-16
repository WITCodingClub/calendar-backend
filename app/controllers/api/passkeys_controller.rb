# frozen_string_literal: true

module Api
  # Passkeys are a second way into an account that Google already vouched for.
  # Onboarding still runs through the WIT Google account, so a passkey never
  # creates an account and never widens who can hold one. It only saves a
  # student from repeating the Google flow on every new device.
  #
  # Both ceremonies are two calls: ask for options (which issues a challenge),
  # then send back what the authenticator produced. The API keeps no session, so
  # the challenge travels as an opaque handle and is consumed on the second call.
  #
  # The ceremony is meant to run on a page of this site, not inside a browser
  # extension: the credential is bound to WEBAUTHN_RP_ID either way, and keeping
  # the prompt on the site keeps the reported origin stable across browsers and
  # builds. See config/initializers/webauthn.rb.
  class PasskeysController < BaseController
    authenticate_with_token except: [ :authentication_options, :authenticate, :exchange ]

    # The page runs the ceremony but holds no JWT, so the extension mints a
    # handoff and the page spends it. Falls through to the normal token check
    # when no handoff is present.
    prepend_before_action :authenticate_user_from_handoff, only: [ :registration_options, :create ]

    def index
      authorize Passkey.new(user: current_user), :index?

      passkeys = current_user.passkeys.recently_used_first.map { |passkey| serialize(passkey) }

      render json: { passkeys: passkeys }, status: :ok
    end

    def registration_options
      authorize Passkey.new(user: current_user), :create?

      render json: Passkeys::Registration.options(current_user), status: :ok
    end

    def create
      authorize Passkey.new(user: current_user), :create?

      passkey = Passkeys::Registration.create!(user: current_user, handle: params[:handle], params: params,
                                               nickname: params[:nickname])

      # Spent only now, so a failed attempt can be retried with the same link.
      PasskeyHandoff.consume(code: params[:handoff], purpose: "register") if params[:handoff].present?

      render json: { passkey: serialize(passkey) }, status: :created
    rescue Passkeys::Failed => e
      render_error e.message, status: :unprocessable_content
    end

    def destroy
      passkey = find_by_any_id(current_user.passkeys, params[:passkey_id])

      if passkey.nil?
        render_error "Passkey not found", status: :not_found
        return
      end

      authorize passkey, :destroy?
      passkey.destroy!

      render json: { message: "Passkey removed" }, status: :ok
    end

    # Unauthenticated: this is the start of a sign-in.
    def authentication_options
      render json: Passkeys::Authentication.options, status: :ok
    end

    # Unauthenticated.
    def authenticate
      passkey = Passkeys::Authentication.verify!(handle: params[:handle], params: params)
      user = passkey.user

      # The page asks for a handoff rather than the token: it has to send this
      # back to the extension through a redirect, and a JWT in a URL lands in
      # browser history and referer headers.
      if ActiveModel::Type::Boolean.new.cast(params[:handoff])
        return render json: { code: PasskeyHandoff.issue!(user: user, purpose: "session") }, status: :ok
      end

      jwt = JsonWebTokenService.issue(user: user, source: "passkey", request: request, passkey: passkey)
      render json: SessionTokenSerializer.new(user, jwt).as_json, status: :ok
    rescue Passkeys::Failed => e
      render_error e.message, status: :unauthorized
    end

    # Mints the code the extension hands to the passkey page so the page can
    # register a passkey for the signed-in account.
    def handoff
      authorize Passkey.new(user: current_user), :create?

      render json: { code: PasskeyHandoff.issue!(user: current_user, purpose: "register") }, status: :ok
    end

    # Unauthenticated: trades the code the page redirected back with for a JWT.
    def exchange
      user = PasskeyHandoff.consume(code: params[:code], purpose: "session")

      if user.nil?
        render_error "That sign-in link has expired. Start again.", status: :unauthorized
        return
      end

      jwt = JsonWebTokenService.issue(user: user, source: "passkey", request: request)
      render json: SessionTokenSerializer.new(user, jwt).as_json, status: :ok
    end

    private

    def authenticate_user_from_handoff
      code = params[:handoff].presence
      return if code.nil?

      # Peeked, not spent: registration is two calls and both need a caller.
      # #create spends it once the passkey is actually stored.
      user = PasskeyHandoff.peek(code: code, purpose: "register")

      if user.nil?
        render_error "That registration link has expired. Start again.", status: :unauthorized
        return
      end

      @current_user = user
    end

    # A spent handoff already says who this is, and the page has no token to
    # send. Anything without one still goes through the usual check.
    def authenticate_user_from_token!
      return if @current_user

      super
    end

    def serialize(passkey)
      {
        id:           passkey.public_id,
        nickname:     passkey.nickname,
        created_at:   passkey.created_at,
        last_used_at: passkey.last_used_at
      }
    end
  end
end

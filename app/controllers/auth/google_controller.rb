# frozen_string_literal: true

module Auth
  class GoogleController < ApplicationController
    skip_before_action :verify_authenticity_token, only: [ :callback ]

    def callback
      auth = request.env["omniauth.auth"]
      raise "Missing omniauth.auth" unless auth

      if calendar_oauth_flow?
        handle_calendar_oauth(auth)
      else
        handle_user_login(auth)
      end
    rescue => e
      Rails.error.report(e, handled: true)

      if calendar_oauth_flow?
        redirect_to "/oauth/failure?error=#{CGI.escape(e.message)}"
      else
        redirect_to new_user_session_path, alert: "Failed to connect with Google. Please try again."
      end
    end

    private

    def calendar_oauth_flow?
      return false if params[:state].blank?

      GoogleSignIn::OauthState.verify_state(params[:state]).present?
    rescue
      false
    end

    # The state names the user who asked for the link. Nothing in the state
    # proves that the browser at the callback belongs to that user: the state
    # URL can be opened anywhere. So:
    #
    # - The state works once (GoogleSignIn::OauthState.consume_state).
    # - A browser signed in as that user (the dashboard) links at once.
    # - A browser signed in as another user links nothing.
    # - A browser with no session (the extension tab) gets a confirm page that
    #   names both accounts. Only a CSRF-protected POST from that page saves the
    #   tokens (Auth::OauthResultsController#link).
    def handle_calendar_oauth(auth)
      state_data = GoogleSignIn::OauthState.consume_state(params[:state])
      raise "Invalid or expired state parameter" unless state_data

      user         = User.find(state_data["user_id"])
      target_email = state_data["email"].presence
      chosen_email = auth.info.email.to_s.strip

      # A state with an email is the old request shape: only that account is
      # accepted. A state without an email accepts any Google account.
      if target_email && chosen_email != target_email
        raise "OAuth email (#{chosen_email}) does not match expected email (#{target_email})"
      end

      if current_user && current_user != user
        raise "You are signed in as a different user. Sign out, then try again."
      end

      linker = GoogleSignIn::AccountLink.new(user)
      tokens = {
        uid:           auth.uid,
        email:         chosen_email,
        access_token:  auth.credentials.token,
        refresh_token: auth.credentials.refresh_token,
        expires_at:    auth.credentials.expires_at
      }

      if current_user
        calendar_id = linker.connect!(**tokens)
        redirect_to "/oauth/success?email=#{CGI.escape(chosen_email)}&calendar_id=#{calendar_id}"
      else
        linker.check!(uid: auth.uid, email: chosen_email)
        GoogleSignIn::AccountLink.discard_pending(session[:pending_google_link])
        session[:pending_google_link] = GoogleSignIn::AccountLink.store_pending(tokens.merge(user_id: user.id))
        redirect_to oauth_confirm_path
      end
    end

    def handle_user_login(auth)
      email = auth.info.email

      unless User.wit_email?(email)
        redirect_to new_user_session_path, alert: "Only @#{User::WIT_EMAIL_DOMAIN} email addresses are allowed."
        return
      end

      user = User.find_or_provision_for_sign_in!(
        email:      email,
        first_name: auth.info.first_name,
        last_name:  auth.info.last_name
      )

      # Only persist the Google credential when calendar scopes were granted
      # (minimal-scope logins omit refresh_token and have no calendar scope).
      granted_scopes = auth.credentials&.token && auth.extra&.raw_info&.fetch("granted_scopes", "")
      if granted_scopes.to_s.include?("calendar")
        begin
          GoogleSignIn::AccountLink.new(user).link!(
            uid:           auth.uid,
            email:         email,
            access_token:  auth.credentials.token,
            refresh_token: auth.credentials.refresh_token,
            expires_at:    auth.credentials.expires_at
          )
        rescue GoogleSignIn::AccountLink::Conflict => e
          # Signing in needs only the verified WIT email. A credential that
          # cannot be saved must not block it.
          Rails.logger.warn("Google sign-in for user #{user.id} did not save calendar access: #{e.message}")
          flash[:alert] = "Signed in. Calendar access was not saved. #{e.message}."
        end
      end

      # Without a remember cookie, :timeoutable signs the person out after 30
      # idle minutes and the session cookie ends when the browser closes.
      user.remember_me = true
      sign_in(:user, user)

      redirect_to after_sign_in_path_for(user), notice: "Welcome, #{user.first_name}!"
    end
  end
end

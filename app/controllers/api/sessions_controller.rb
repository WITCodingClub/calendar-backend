# frozen_string_literal: true

module Api
  # Lets someone see where their account is signed in, and end any of it.
  class SessionsController < ApiController
    # GET /api/user/sessions
    def index
      authorize UserSession.new(user: current_user), :index?

      sessions = current_user.user_sessions.active.recent_first.map { |s| serialize(s) }

      render json: { sessions: sessions }, status: :ok
    end

    # DELETE /api/user/sessions/:session_id
    def destroy
      session = find_by_any_id(UserSession, params[:session_id])
      session = nil unless session&.user_id == current_user.id

      if session.nil?
        render json: { error: "Session not found" }, status: :not_found
        return
      end

      authorize session, :destroy?
      session.revoke!(reason: "signed out by the user")

      render json: { message: "Session ended" }, status: :ok
    end

    # POST /api/user/sessions/revoke_all
    #
    # Keeps the caller signed in by default: someone clearing a lost device
    # should not have to sign back in on the device they are holding.
    def revoke_all
      authorize UserSession.new(user: current_user), :destroy?

      keep = ActiveModel::Type::Boolean.new.cast(params[:keep_current]) != false

      UserSession.revoke_all_for(
        current_user,
        reason: "user ended all sessions",
        except: keep ? current_session : nil
      )

      render json: { message: "Other sessions ended" }, status: :ok
    end

    private

    def serialize(session)
      {
        id:           session.public_id,
        device:       session.device_label,
        source:       session.source,
        passkey:      session.passkey&.nickname,
        ip_address:   session.ip_address,
        created_at:   session.created_at,
        last_seen_at: session.last_seen_at,
        expires_at:   session.expires_at,
        current:      session.id == current_session&.id
      }
    end
  end
end

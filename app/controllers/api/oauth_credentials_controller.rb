# frozen_string_literal: true

module Api
  class OauthCredentialsController < BaseController
    authenticate_with_token

    # GET /api/user/oauth_credentials
    def index
      authorize current_user, :show?

      credentials = current_user.oauth_credentials.includes(:course_calendar).map do |c|
        {
          id:           c.public_id,
          email:        c.email,
          provider:     c.provider,
          has_calendar: c.course_calendar.present?,
          calendar_id:  c.course_calendar&.external_calendar_id,
          # Where the course events go. Microsoft only, nil without a calendar.
          placement:    c.course_calendar&.placement,
          removable:    c.removable?,
          created_at:   c.created_at,
          needs_reauth: c.needs_reauth?,
          token_revoked: c.token_revoked?
        }
      end

      render json: { oauth_credentials: credentials }, status: :ok
    end

    # DELETE /api/user/oauth_credentials/:credential_id
    def destroy
      credential_id = params[:credential_id]

      if credential_id.blank?
        render_error "credential_id is required", status: :bad_request
        return
      end

      credential = find_by_any_id(OauthCredential, credential_id)
      credential = nil unless credential&.user_id == current_user.id

      if credential.nil?
        render_error "OAuth credential not found", status: :not_found
        return
      end

      authorize credential, :destroy?

      unless credential.removable?
        render_error "Cannot disconnect your last Google account.", status: :unprocessable_content
        return
      end

      credential.destroy!
      render json: { message: "OAuth credential disconnected successfully" }, status: :ok
    rescue => e
      Rails.logger.error("Error disconnecting OAuth credential for user #{current_user.id}: #{e.message}")
      render_error "Failed to disconnect OAuth credential", status: :internal_server_error
    end
  end
end

# frozen_string_literal: true

module Api
  class OauthCredentialsController < BaseController
    authenticate_with_token

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

    def destroy
      if params[:credential_id].blank?
        render_error "credential_id is required", status: :bad_request
        return
      end

      credential = find_by_any_id(current_user.oauth_credentials, params[:credential_id])
      return render_error("OAuth credential not found", status: :not_found) if credential.nil?

      authorize credential, :destroy?

      if OauthCredentials::Disconnect.call(credential)
        render json: { message: "OAuth credential disconnected successfully" }, status: :ok
      else
        render_error "Cannot disconnect your last Google account.", status: :unprocessable_content
      end
    end
  end
end

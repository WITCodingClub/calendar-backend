module Api
  class UsersController < ApplicationController
    include JsonWebTokenAuthenticatable

    skip_before_action :verify_authenticity_token
    skip_before_action :authenticate_user_from_token!, only: [:onboard]

    def onboard
      #   takes email as it's one param
      email = params[:email]

      if email.blank?
        render json: { error: "Email is required" }, status: :bad_request
        return
      end

      user = User.find_or_create_by_email(email)

      # return JSON with a jwt token for the user. this token should be signed, and never expire
      token = JsonWebTokenService.encode({ user_id: user.id }, nil) # nil expiration for never expiring

      render json: { jwt: token }, status: :ok
    rescue StandardError => e
      Rails.logger.error("Error in onboarding user: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      render json: { error: "Failed to onboard user" }, status: :internal_server_error

    end

    def request_g_cal
      raw = request.raw_post

      emails =
        begin
          parsed = JSON.parse(raw)
          case parsed
          when Array
            parsed
          when Hash
            parsed["emails"] || parsed["_json"] || []
          else
            []
          end
        rescue JSON::ParserError
          []
        end

      emails = emails.compact.map(&:to_s).map(&:strip).reject(&:empty?)

      # if there are no emails provided, return bad request
      if emails.empty?
        render json: { error: "At least one email is required" }, status: :bad_request
        return
      end

      # For each email, create/update Email record with g_cal = true
      emails.each do |email_address|
        email_record = current_user.emails.find_or_initialize_by(email: email_address)
        email_record.g_cal = true
        email_record.save!
      end

      # Generate OAuth URLs for emails that don't have credentials yet
      oauth_urls = []

      emails.each do |email_address|
        # Check if this email already has OAuth credentials
        next if current_user.google_credential_for_email(email_address).present?

        # Generate state parameter
        state = GoogleOauthStateService.generate_state(
          user_id: current_user.id,
          email: email_address
        )

        # Build OAuth URL
        oauth_url = "/auth/google_oauth2?state=#{CGI.escape(state)}"

        oauth_urls << {
          email: email_address,
          oauth_url: oauth_url
        }
      end

      # If all emails are already OAuth'd, check if calendar needs to be created/shared
      if oauth_urls.empty?
        # All emails have credentials, ensure calendar is created and shared
        service = GoogleCalendarService.new(current_user)
        calendar_id = service.create_or_get_course_calendar

        render json: {
          message: "All emails already connected",
          calendar_id: calendar_id,
          oauth_urls: []
        }, status: :ok
      else
        render json: {
          message: "OAuth required for some emails",
          oauth_urls: oauth_urls
        }, status: :ok
      end
    rescue StandardError => e
      Rails.logger.error("Error requesting Google Calendar for user #{current_user.id}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      render json: { error: "Failed to request Google Calendar" }, status: :internal_server_error
    end


  end
end

# frozen_string_literal: true

module Api
  class NotificationsController < BaseController
    authenticate_with_token

    # GET /api/user/notifications_status
    def show
      authorize current_user, :show?
      render json: {
        notifications_disabled:       current_user.notifications_disabled?,
        notifications_disabled_until: current_user.notifications_disabled_until
      }, status: :ok
    end

    # POST /api/user/notifications/disable
    def disable
      authorize current_user, :update?

      duration_provided  = params.key?(:duration) && params[:duration].present?
      duration_seconds   = params[:duration].to_i if duration_provided

      if duration_provided
        if duration_seconds < 0
          render_error "Duration cannot be negative", status: :bad_request
          return
        end

        if duration_seconds > 100.years.to_i
          render_error "Duration cannot exceed 100 years", status: :bad_request
          return
        end
      end

      if duration_provided && duration_seconds > 0
        current_user.disable_notifications!(duration: duration_seconds.seconds)
      else
        current_user.disable_notifications!
      end

      render json: {
        message:                      "Notifications disabled",
        notifications_disabled:       true,
        notifications_disabled_until: current_user.notifications_disabled_until
      }, status: :ok
    rescue => e
      Rails.logger.error("Error disabling notifications for user #{current_user.id}: #{e.message}")
      render_error "Failed to disable notifications", status: :internal_server_error
    end

    # POST /api/user/notifications/enable
    def enable
      authorize current_user, :update?

      current_user.enable_notifications!
      current_user.update_column(:calendar_needs_sync, true) # rubocop:disable Rails/SkipsModelValidations
      GoogleCalendarSyncJob.perform_later(current_user, force: true)

      render json: {
        message:                      "Notifications enabled",
        notifications_disabled:       false,
        notifications_disabled_until: nil
      }, status: :ok
    rescue => e
      Rails.logger.error("Error enabling notifications for user #{current_user.id}: #{e.message}")
      render_error "Failed to enable notifications", status: :internal_server_error
    end
  end
end

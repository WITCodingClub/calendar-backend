# frozen_string_literal: true

module Api
  class NotificationsController < BaseController
    authenticate_with_token

    def show
      authorize current_user, :show?
      render json: {
        notifications_disabled:       current_user.notifications_disabled?,
        notifications_disabled_until: current_user.notifications_disabled_until
      }, status: :ok
    end

    # Send "disabled": true to turn notifications off, with an optional
    # "duration" in seconds, or "disabled": false to turn them on again.
    def update
      unless params.key?(:disabled)
        render_error "disabled is required", status: :bad_request
        return
      end

      ActiveModel::Type::Boolean.new.cast(params[:disabled]) ? disable : enable
    end

    private

    def disable
      authorize current_user, :update?

      duration = params[:duration].presence
      if duration
        unless duration.to_s.match?(/\A-?\d+\z/)
          render_error "Duration must be a whole number of seconds", status: :bad_request
          return
        end

        duration = duration.to_i
        if duration < 0
          render_error "Duration cannot be negative", status: :bad_request
          return
        end

        if duration > 100.years.to_i
          render_error "Duration cannot exceed 100 years", status: :bad_request
          return
        end
      end

      Notifications::Toggle.call(current_user, disabled: true, duration: duration&.positive? ? duration.seconds : nil)
      render_state "Notifications disabled"
    end

    def enable
      authorize current_user, :update?

      Notifications::Toggle.call(current_user, disabled: false)
      render_state "Notifications enabled"
    end

    def render_state(message)
      render json: {
        message:                      message,
        notifications_disabled:       current_user.notifications_disabled?,
        notifications_disabled_until: current_user.notifications_disabled_until
      }, status: :ok
    end
  end
end

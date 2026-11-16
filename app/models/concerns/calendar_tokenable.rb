# frozen_string_literal: true

module CalendarTokenable
  extend ActiveSupport::Concern

  def cal_url
    generate_calendar_token if calendar_token.blank?

    url_options = Rails.application.config.action_controller.default_url_options || {}

    Rails.application.routes.url_helpers.calendar_url(
      calendar_token,
      format: :ics,
      **url_options
    )
  end

  def cal_url_with_extension
    "#{cal_url}.ics"
  end

  def generate_calendar_token
    return if calendar_token.present?

    self.calendar_token = SecureRandom.urlsafe_base64(32)
    # The unique index on calendar_token catches a collision.
    save! if persisted?
  end
end

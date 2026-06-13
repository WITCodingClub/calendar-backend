# frozen_string_literal: true

class GoogleCalendarHistoricalSyncJob < ApplicationJob
  queue_as :low

  limits_concurrency to: 1, key: ->(user, force: false) { "google_calendar_historical_user_#{user.id}" }

  def perform(user, force: false)
    user.sync_historical_events(force: force)
  end
end

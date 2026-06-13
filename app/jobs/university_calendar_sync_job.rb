# frozen_string_literal: true

# Syncs university calendar events from the 25Live ICS feed and also refreshes
# 25Live reference data (organizations, event categories, resources) via
# External::TwentyFiveLiveService. Scheduled to run daily at 3am via Solid Queue.
class UniversityCalendarSyncJob < ApplicationJob
  queue_as :low

  limits_concurrency to: 1, key: -> { "university_calendar_sync" }

  def perform
    Rails.logger.info("Starting university calendar sync")

    # Refresh 25Live reference data (organizations, categories, resources)
    begin
      External::TwentyFiveLiveService.call
      Rails.logger.info("25Live reference data sync complete")
    rescue => e
      Rails.logger.warn("25Live reference data sync failed (non-fatal): #{e.message}")
    end

    result = UniversityCalendarIcsService.call

    Rails.logger.info("University calendar ICS sync complete: #{result}")

    any_changes = result[:created].positive? || result[:updated].positive? || result[:cancelled].positive?

    if any_changes
      changed = Array(result[:changed_categories])
      holidays_changed = (changed & %w[holiday study_day]).any?
      trigger_user_calendar_syncs(holidays_changed: holidays_changed)
    end

    update_term_dates_from_events

    result
  end

  private

  def trigger_user_calendar_syncs(holidays_changed:)
    if holidays_changed
      trigger_sync_for_all_users
    else
      trigger_sync_for_opted_in_users
    end
  end

  def trigger_sync_for_all_users
    Rails.logger.info("Holiday changes detected - syncing all users")

    User.joins(oauth_credentials: :google_calendar)
        .distinct
        .find_each do |user|
          GoogleCalendarSyncJob.perform_later(user, force: true)
        end
  end

  def trigger_sync_for_opted_in_users
    Rails.logger.info("Non-holiday changes detected - syncing opted-in users only")

    User.joins(:user_extension_config)
        .where(user_extension_configs: { sync_university_events: true })
        .joins(oauth_credentials: :google_calendar)
        .distinct
        .find_each do |user|
          GoogleCalendarSyncJob.perform_later(user, force: true)
        end
  end

  def update_term_dates_from_events
    current_year = Time.zone.today.year

    Term.where(year: (current_year - 1)..).find_each do |term|
      dates = UniversityCalendarEvent.detect_term_dates(term.year, term.season)

      updates = {}
      updates[:start_date] = dates[:start_date] if dates[:start_date] && term.start_date.nil?
      updates[:end_date]   = dates[:end_date]   if dates[:end_date]   && term.end_date.nil?

      term.update!(updates) if updates.any?
      Rails.logger.info("Updated term #{term.name} with dates: #{updates}") if updates.any?
    rescue => e
      Rails.logger.warn("Failed to extract dates for #{term.name}: #{e.message}")
    end
  end
end

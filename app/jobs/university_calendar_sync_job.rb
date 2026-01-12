# frozen_string_literal: true

# Job to sync university calendar events from the ICS feed.
#
# This job:
# 1. Fetches and parses the ICS feed via UniversityCalendarIcsService
# 2. Triggers GoogleCalendarSyncJob for ALL users when holidays change (auto-sync)
# 3. Triggers sync only for opted-in users when other events change
# 4. Attempts to update Term dates from newly detected events
#
# Scheduled to run daily at 3am via Solid Queue recurring configuration.
#
class UniversityCalendarSyncJob < ApplicationJob
  queue_as :low

  # Prevent concurrent runs
  limits_concurrency to: 1, key: -> { "university_calendar_sync" }

  def perform
    Rails.logger.info("Starting university calendar sync")

    # Capture before/after holiday count to detect changes
    holiday_count_before = UniversityCalendarEvent.holidays.count

    result = UniversityCalendarIcsService.call

    Rails.logger.info("University calendar sync complete: #{result}")

    # Check if holidays changed
    holiday_count_after = UniversityCalendarEvent.holidays.count
    holidays_changed = holiday_count_before != holiday_count_after || result[:updated].positive?

    # If events changed, trigger calendar re-sync for affected users
    if result[:created].positive? || result[:updated].positive?
      trigger_user_calendar_syncs(holidays_changed: holidays_changed)
    end

    # Attempt to update term dates from new data
    update_term_dates_from_events

    result
  end

  private

  # Trigger calendar syncs for users based on what changed
  # @param holidays_changed [Boolean] whether holidays were added/updated
  def trigger_user_calendar_syncs(holidays_changed:)
    if holidays_changed
      # Holidays affect ALL users - trigger sync for everyone with a calendar
      trigger_sync_for_all_users
    else
      # Only trigger sync for users who opted in to non-holiday events
      trigger_sync_for_opted_in_users
    end
  end

  # Trigger sync for all users with a Google Calendar
  def trigger_sync_for_all_users
    Rails.logger.info("Holiday changes detected - syncing all users")

    User.joins(oauth_credentials: :google_calendar)
        .distinct
        .find_each do |user|
          GoogleCalendarSyncJob.perform_later(user, force: true)
    end
  end

  # Trigger sync only for users who have opted in to university events
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

  # Attempt to update term dates from university calendar events
  def update_term_dates_from_events
    # Only update terms that don't have dates set
    Term.where(start_date: nil).or(Term.where(end_date: nil)).find_each do |term|
      dates = UniversityCalendarEvent.detect_term_dates(term.year, term.season)

      updates = {}
      updates[:start_date] = dates[:start_date] if dates[:start_date] && term.start_date.nil?
      updates[:end_date] = dates[:end_date] if dates[:end_date] && term.end_date.nil?

      if updates.any?
        term.update!(updates)
        Rails.logger.info("Updated term #{term.name} with dates: #{updates}")
      end
    rescue => e
      Rails.logger.warn("Failed to extract dates for #{term.name}: #{e.message}")
    end
  end

end

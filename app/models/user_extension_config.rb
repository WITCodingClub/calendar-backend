# frozen_string_literal: true

class UserExtensionConfig < ApplicationRecord
  include EncodedIds::HashidIdentifiable

  set_public_id_prefix :uec

  belongs_to :user

  before_save :clear_categories_when_sync_disabled
  after_update :sync_calendar_if_settings_changed

  private

  def clear_categories_when_sync_disabled
    return unless will_save_change_to_sync_university_events? && !sync_university_events

    self.university_event_categories = []
  end

  def sync_calendar_if_settings_changed
    return unless saved_change_to_default_color_lecture? || saved_change_to_default_color_lab? ||
                  saved_change_to_sync_university_events? || saved_change_to_university_event_categories?

    GoogleCalendarSyncJob.perform_later(user, force: true)
  end
end

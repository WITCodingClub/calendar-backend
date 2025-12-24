# frozen_string_literal: true

# == Schema Information
#
# Table name: user_extension_configs
# Database name: primary
#
#  id                          :bigint           not null, primary key
#  advanced_editing            :boolean          default(FALSE), not null
#  default_color_lab           :string           default("#f6bf26"), not null
#  default_color_lecture       :string           default("#039be5"), not null
#  military_time               :boolean          default(FALSE), not null
#  sync_university_events      :boolean          default(FALSE), not null
#  university_event_categories :jsonb
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  user_id                     :bigint           not null
#
# Indexes
#
#  index_user_extension_configs_on_user_id  (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class UserExtensionConfig < ApplicationRecord
  include PublicIdentifiable

  set_public_id_prefix :uec

  belongs_to :user

  # Trigger calendar sync when settings change that affect calendar events
  after_update :sync_calendar_if_settings_changed

  private

  def sync_calendar_if_settings_changed
    # Sync if colors or university event settings changed
    if saved_change_to_default_color_lecture? ||
       saved_change_to_default_color_lab? ||
       saved_change_to_sync_university_events? ||
       saved_change_to_university_event_categories?
      # Queue a forced sync to update all calendar events
      GoogleCalendarSyncJob.perform_later(user, force: true)
    end
  end

end

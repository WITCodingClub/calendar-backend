# frozen_string_literal: true

# == Schema Information
#
# Table name: user_extension_configs
# Database name: primary
#
#  id                    :bigint           not null, primary key
#  advanced_editing      :boolean          default(FALSE), not null
#  default_color_lab     :string           default("#f6bf26"), not null
#  default_color_lecture :string           default("#039be5"), not null
#  military_time         :boolean          default(FALSE), not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  user_id               :bigint           not null
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
  belongs_to :user

  # Trigger calendar sync when default colors change
  after_update :sync_calendar_if_colors_changed

  private

  def sync_calendar_if_colors_changed
    # Only sync if lecture or lab colors changed
    if saved_change_to_default_color_lecture? || saved_change_to_default_color_lab?
      # Queue a forced sync to update all calendar events with new colors
      GoogleCalendarSyncJob.perform_later(user, force: true)
    end
  end

end

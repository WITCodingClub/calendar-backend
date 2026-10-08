# frozen_string_literal: true

# Issue #564: a uni_cal_category row sits above the uni_cal_global row in
# PreferenceResolver. Old extension builds wrote a color on each category row,
# so these colors hide the university wide color the user picked later.
#
# For each user with a university wide color, clear the color of each category
# row. The other fields of these rows stay. Mark each changed user for a sync,
# so the next NightlyCalendarSyncJob run gives the events the university wide
# color.
class ClearCategoryColorsUnderUniversityWideColor < ActiveRecord::Migration[8.1]
  UNI_CAL_CATEGORY_SCOPE = 2 # CalendarPreference.scopes["uni_cal_category"]
  UNI_CAL_GLOBAL_SCOPE   = 3 # CalendarPreference.scopes["uni_cal_global"]
  BATCH_SIZE = 1_000

  class MigrationCalendarPreference < ActiveRecord::Base
    self.table_name = "calendar_preferences"
  end

  class MigrationUser < ActiveRecord::Base
    self.table_name = "users"
  end

  def up
    now = Time.current
    changed_users = 0

    university_colors = MigrationCalendarPreference.where(scope: UNI_CAL_GLOBAL_SCOPE).where.not(color_id: nil)

    university_colors.in_batches(of: BATCH_SIZE) do |batch|
      stale = MigrationCalendarPreference.where(scope: UNI_CAL_CATEGORY_SCOPE, user_id: batch.select(:user_id))
                                         .where.not(color_id: nil)
      user_ids = stale.distinct.pluck(:user_id)
      next if user_ids.empty?

      MigrationCalendarPreference.transaction do
        stale.update_all(color_id: nil, updated_at: now) # rubocop:disable Rails/SkipsModelValidations
        MigrationUser.where(id: user_ids).update_all(calendar_needs_sync: true) # rubocop:disable Rails/SkipsModelValidations
      end
      changed_users += user_ids.size
    end

    say "Cleared category colors under a university wide color for #{changed_users} user(s)"
  end

  def down
    # The cleared category colors are not kept anywhere, so they cannot come
    # back. The rows stay as they are.
    say "Nothing to revert: cleared category colors cannot be restored"
  end
end

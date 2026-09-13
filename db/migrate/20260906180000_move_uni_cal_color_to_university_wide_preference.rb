# frozen_string_literal: true

# Issue #498: the extension set the university calendar color by writing one
# uni_cal_category preference per category, from a category list it kept itself.
# That list was missing study_day, so Study Day kept the system default color
# (Graphite) while every other university event used the chosen color.
#
# The uni_cal_global scope now covers every university event in one row, so move
# the color there. A user whose category colors are all the same picked one
# color for the whole university calendar, so the color moves and the category
# overrides go. A user with different colors per category chose them on purpose,
# so leave that user alone.
class MoveUniCalColorToUniversityWidePreference < ActiveRecord::Migration[8.1]
  UNI_CAL_CATEGORY_SCOPE = 2 # CalendarPreference.scopes["uni_cal_category"]
  UNI_CAL_GLOBAL_SCOPE   = 3 # CalendarPreference.scopes["uni_cal_global"]

  # A category row is worth keeping when it carries something other than color.
  # An empty reminder list means "no reminders at all", which is a choice the
  # user made, so test reminder_settings for nil rather than for blank.
  OTHER_FIELDS = %w[title_template description_template location_template visibility].freeze

  class MigrationCalendarPreference < ActiveRecord::Base
    self.table_name = "calendar_preferences"
  end

  class MigrationUser < ActiveRecord::Base
    self.table_name = "users"
  end

  def up
    users_with_uni_cal_global = MigrationCalendarPreference
                                .where(scope: UNI_CAL_GLOBAL_SCOPE)
                                .distinct.pluck(:user_id)

    candidates = MigrationCalendarPreference.where(scope: UNI_CAL_CATEGORY_SCOPE)
    candidates = candidates.where.not(user_id: users_with_uni_cal_global) if users_with_uni_cal_global.any?

    now = Time.current
    new_rows = []
    clear_ids = []
    delete_ids = []

    candidates.order(:user_id, :id).group_by(&:user_id).each do |user_id, preferences|
      colors = preferences.filter_map(&:color_id).uniq
      next unless colors.one?

      new_rows << { user_id: user_id, scope: UNI_CAL_GLOBAL_SCOPE, event_type: nil,
                    color_id: colors.first, created_at: now, updated_at: now }

      colored = preferences.select { |pref| pref.color_id.present? }
      keep, drop = colored.partition { |pref| carries_more_than_color?(pref) }
      clear_ids.concat(keep.map(&:id))
      delete_ids.concat(drop.map(&:id))
    end

    return if new_rows.empty?

    MigrationCalendarPreference.transaction do
      MigrationCalendarPreference.insert_all(new_rows)
      MigrationCalendarPreference.where(id: clear_ids).update_all(color_id: nil, updated_at: now) if clear_ids.any? # rubocop:disable Rails/SkipsModelValidations
      MigrationCalendarPreference.where(id: delete_ids).delete_all if delete_ids.any?
      MigrationUser.where(id: new_rows.pluck(:user_id)).update_all(calendar_needs_sync: true) # rubocop:disable Rails/SkipsModelValidations
    end

    say "Moved the university calendar color to a university wide preference for #{new_rows.size} user(s)"
  end

  def down
    # The category rows this dropped cannot be told apart from ones a user never
    # had, so there is nothing safe to restore.
    say "Nothing to revert: university wide color preferences are kept"
  end

  private

  def carries_more_than_color?(preference)
    return true unless preference.reminder_settings.nil?

    OTHER_FIELDS.any? { |field| preference[field].present? }
  end
end

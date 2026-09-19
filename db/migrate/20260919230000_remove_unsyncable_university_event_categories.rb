# frozen_string_literal: true

# Issue #621: campus_event, meeting, exhibit, announcement, and other no longer
# sync. Remove them from each saved selection, so a later return of a category
# does not turn it back on for people who picked it before.
#
# Mark each person who had one of them selected for a sync. The next
# NightlyCalendarSyncJob run then deletes those events from their calendars.
class RemoveUnsyncableUniversityEventCategories < ActiveRecord::Migration[8.1]
  REMOVED_CATEGORIES = %w[campus_event meeting exhibit announcement other].freeze

  def up
    removed = "ARRAY[#{REMOVED_CATEGORIES.map { |category| connection.quote(category) }.join(', ')}]"

    execute <<~SQL.squish
      UPDATE users SET calendar_needs_sync = TRUE
      WHERE id IN (
        SELECT user_id FROM user_extension_configs
        WHERE university_event_categories ?| #{removed}
      )
    SQL

    execute <<~SQL.squish
      UPDATE user_extension_configs
      SET university_event_categories = COALESCE(
        (
          SELECT jsonb_agg(element.category ORDER BY element.position)
          FROM jsonb_array_elements_text(university_event_categories)
            WITH ORDINALITY AS element(category, position)
          WHERE element.category <> ALL (#{removed})
        ),
        '[]'::jsonb
      )
      WHERE university_event_categories ?| #{removed}
    SQL
  end

  # The removed selections are gone, and nothing syncs these categories anymore.
  def down; end
end

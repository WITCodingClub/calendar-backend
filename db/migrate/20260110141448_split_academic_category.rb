# frozen_string_literal: true

class SplitAcademicCategory < ActiveRecord::Migration[8.1]
  def up
    # Re-categorize existing "academic" events using the updated infer_category logic
    safety_assured do
      execute <<-SQL.squish
      UPDATE university_calendar_events
      SET category = CASE
        WHEN LOWER(summary) LIKE '%classes begin%' OR LOWER(summary) LIKE '%classes end%'
          OR LOWER(summary) LIKE '%first day of classes%' OR LOWER(summary) LIKE '%last day of classes%'
          OR LOWER(summary) LIKE '%semester begins%' OR LOWER(summary) LIKE '%semester ends%'
          OR LOWER(summary) LIKE '%term begins%' OR LOWER(summary) LIKE '%term ends%'
          THEN 'term_dates'
        WHEN LOWER(summary) LIKE '%final exam%' OR LOWER(summary) LIKE '%finals week%'
          OR LOWER(summary) LIKE '%final week%' OR LOWER(summary) LIKE '%exam period%'
          OR LOWER(summary) LIKE '%examination period%'
          THEN 'finals'
        WHEN LOWER(summary) LIKE '%commencement%' OR LOWER(summary) LIKE '%graduation%'
          OR LOWER(summary) LIKE '%convocation%' OR LOWER(summary) LIKE '%conferral%'
          THEN 'graduation'
        WHEN LOWER(summary) LIKE '%registration%' OR LOWER(summary) LIKE '%enrollment%'
          OR LOWER(summary) LIKE '%add/drop%' OR LOWER(summary) LIKE '%add drop%'
          OR LOWER(summary) LIKE '%course selection%'
          THEN 'registration'
        WHEN LOWER(summary) LIKE '%deadline%' OR LOWER(summary) LIKE '%last day to%'
          OR LOWER(summary) LIKE '%withdrawal%' OR LOWER(summary) LIKE '%due date%'
          OR LOWER(summary) LIKE '%tuition due%' OR LOWER(summary) LIKE '%payment due%'
          OR LOWER(summary) LIKE '%grade submission%'
          THEN 'deadline'
        ELSE 'academic'
      END
      WHERE category = 'academic'
      SQL
    end

    # Migrate user preferences: expand "academic" to include all new granular categories
    # This ensures users who had "academic" selected don't lose visibility
    # Note: "academic" remains as a catch-all, so we add it back along with the specific categories
    new_categories = %w[term_dates registration deadline finals graduation academic]

    UserExtensionConfig.where("university_event_categories @> ?", '["academic"]').find_each do |config|
      categories = config.university_event_categories || []
      categories = (categories - ["academic"] + new_categories).uniq
      config.update_column(:university_event_categories, categories)
    end
  end

  def down
    # Revert new categories back to "academic"
    # Note: "academic" stays as "academic" since it's the catch-all
    new_categories = %w[term_dates registration deadline finals graduation]

    safety_assured do
      execute <<-SQL.squish
        UPDATE university_calendar_events
        SET category = 'academic'
        WHERE category IN ('term_dates', 'registration', 'deadline', 'finals', 'graduation')
      SQL
    end

    # Revert user preferences: consolidate granular categories back to just "academic"
    all_granular = %w[term_dates registration deadline finals graduation academic]
    UserExtensionConfig.where("university_event_categories ?| array[:cats]", cats: all_granular).find_each do |config|
      categories = config.university_event_categories || []
      categories = (categories - all_granular + ["academic"]).uniq
      config.update_column(:university_event_categories, categories)
    end
  end

end

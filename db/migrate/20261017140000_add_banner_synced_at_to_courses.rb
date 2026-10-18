# frozen_string_literal: true

# When Banner last confirmed a section's details, meeting times, faculty, and
# seats. Courses::Processor skips Banner for a section the nightly sync
# confirmed recently, and asks Banner for the rest. A null value means that
# Banner has not confirmed the section, so it is asked again.
class AddBannerSyncedAtToCourses < ActiveRecord::Migration[8.1]
  def change
    add_column :courses, :banner_synced_at, :datetime
  end
end

# frozen_string_literal: true

# When the nightly catalog sync last finished a term: the sections
# (Catalog::CourseDataSyncJob) and the course details
# (Catalog::CourseDetailsSyncJob). Catalog::Freshness reports them, so the
# MCP advisory gives the time of a full run, not of one course.
class AddSyncedAtColumnsToTerms < ActiveRecord::Migration[8.1]
  def change
    add_column :terms, :sections_synced_at, :datetime
    add_column :terms, :details_synced_at, :datetime
  end
end

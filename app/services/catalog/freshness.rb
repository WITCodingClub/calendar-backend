# frozen_string_literal: true

module Catalog
  # The official Wentworth sources of the catalog, how often WIT Calendar
  # copies each one, and when it last did. The MCP advisory
  # (McpTools::BaseTool) sends it, so a student can see how old the data is.
  class Freshness
    CACHE_KEY = "catalog/freshness"
    # The times change only when a sync writes them with update_column, which
    # skips callbacks, so the cache has only a TTL.
    CACHE_TTL = 10.minutes

    # The daily run is course_data_sync in config/recurring.yml.
    SOURCES = [
      {
        key:      :sections,
        data:     "Course sections: meeting times, rooms, instructors, and seats",
        source:   "Wentworth Banner class schedule (LeopardWeb)",
        schedule: "Every day at 4 AM Eastern, for the current and future terms. A student's own courses also " \
                  "refresh when the extension processes their term."
      },
      {
        key:      :course_details,
        data:     "Course descriptions, credits, prerequisites, corequisites, and restrictions",
        source:   "Wentworth Banner course catalog",
        schedule: "Each course at most once every #{CourseDetailsSync::FRESH_FOR.in_days.to_i} days, " \
                  "in the daily 4 AM Eastern run."
      }
    ].freeze

    def self.call
      last = Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) { last_refreshed }

      SOURCES.map { |source| source.except(:key).merge(last_refreshed_at: last[source[:key]]) }
    end

    # Plain strings, not times, so the cache holds plain values.
    def self.last_refreshed
      {
        sections:       Course.maximum(:banner_synced_at)&.iso8601,
        course_details: CatalogCourse.maximum(:details_fetched_at)&.iso8601
      }
    end
  end
end

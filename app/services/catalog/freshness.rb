# frozen_string_literal: true

module Catalog
  # The official Wentworth sources of the data that the MCP tools give, how
  # often WIT Calendar copies each one, and when it last did. The MCP advisory
  # (McpTools::BaseTool) sends it, so a student can see how old the data is.
  #
  # A source of term data gives one time for each term that the nightly sync
  # covers (the current and future terms). The time is when a full run for
  # that term finished, not when one course changed.
  class Freshness
    CACHE_KEY = "catalog/freshness"
    # The times change only in jobs that write them with update_column, which
    # skips callbacks, so the cache has only a TTL.
    CACHE_TTL = 10.minutes

    # The daily run is course_data_sync in config/recurring.yml, the seat
    # refresh is catalog_seat_refresh, the weekly one is university_calendar_sync,
    # and the monthly one is degree_requirements_current_year.
    SOURCES = {
      sections:            {
        data:     "Course sections: meeting times, rooms, instructors, and seats",
        source:   "Wentworth Banner class schedule (LeopardWeb)",
        schedule: "Every day at 4 AM Eastern, for the current and future terms. A past term is not refreshed " \
                  "after it ends. Seats also every 30 minutes, from the time a term's sections are listed until " \
                  "#{SeatRefreshJob::ADD_DROP.in_days.to_i} days after its classes start."
      },
      course_details:      {
        data:     "Course descriptions, credits, prerequisites, corequisites, and restrictions",
        source:   "Wentworth Banner course catalog",
        schedule: "Each course at most once every #{CourseDetailsSync::FRESH_FOR.in_days.to_i} days, in the " \
                  "daily 4 AM Eastern run, for the current and future terms. A course that is not offered in " \
                  "those terms keeps the details of the last term that offered it."
      },
      finals:              {
        data:     "Final exam dates, times, and rooms",
        source:   "Wentworth Registrar finals schedule (PDF)",
        schedule: "When an admin uploads a new schedule from the Registrar."
      },
      university_calendar: {
        data:     "Holidays, term dates, registration, deadlines, and finals week",
        source:   "Wentworth academic calendar (25Live)",
        schedule: "Every Saturday at 2 AM Eastern."
      },
      degree_requirements: {
        data:     "Degree programs, plans of study, and elective lists for each catalog year",
        source:   "Wentworth academic catalog (catalog.wit.edu)",
        schedule: "On the 2nd of each month at 3 AM Eastern, for the current catalog year and the year before. " \
                  "Older catalog years do not change."
      }
    }.freeze

    TERM_SOURCES = %i[sections course_details finals].freeze

    def self.call(keys)
      last = Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) { last_refreshed }

      keys.map do |key|
        source = SOURCES.fetch(key).merge(key: key.to_s)
        if TERM_SOURCES.include?(key)
          source.merge(terms: last[:terms].map { |term| term.slice(:term_uid, :term).merge(last_refreshed_at: term[key]) })
        else
          source.merge(last_refreshed_at: last[key])
        end
      end
    end

    # Plain strings, not records or times, so the cache holds plain values.
    def self.last_refreshed
      terms  = Term.current_and_future.to_a
      finals = FinalsSchedule.completed.where(term: terms).group(:term_id).maximum(:processed_at)

      {
        terms:               terms.map do |term|
          {
            term_uid:       term.uid,
            term:           term.name,
            sections:       term.sections_synced_at&.iso8601,
            course_details: term.details_synced_at&.iso8601,
            finals:         finals[term.id]&.iso8601
          }
        end,
        university_calendar: UniversityCalendarEvent.maximum(:last_fetched_at)&.iso8601,
        degree_requirements: CatalogYear.maximum(:imported_at)&.iso8601
      }
    end
  end
end

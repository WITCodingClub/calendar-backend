# frozen_string_literal: true

module UniversityCalendar
  class BackfillJob < ApplicationJob
    queue_as :low

    # The concurrency group is part of every lock key, so it must not change when
    # the class is renamed. Jobs in the queue hold locks under this name.
    CONCURRENCY_GROUP = "UniversityCalendarBackfillJob"

    limits_concurrency to: 1, group: CONCURRENCY_GROUP, key: ->(*) { "university_calendar_backfill" }

    def perform(start_date, end_date)
      start_date = start_date.to_date
      end_date   = end_date.to_date

      Rails.logger.info("Starting university calendar backfill: #{start_date} – #{end_date}")

      url    = UniversityCalendar::IcsImport.backfill_url(start_date, end_date)
      result = UniversityCalendar::IcsImport.call(ics_url: url)

      Rails.logger.info("University calendar backfill complete: #{result}")
      result
    end
  end
end

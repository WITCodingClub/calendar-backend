# frozen_string_literal: true

module Catalog
  # Refreshes the seat counts (Catalog::SeatRefresh) of each term that students
  # can register for, every 30 minutes. The nightly Catalog::CourseDataSyncJob
  # refreshes everything else once a day.
  #
  # A term is in its registration window from the time Banner lists its
  # sections until add/drop ends, ADD_DROP after the first day of classes.
  class SeatRefreshJob < ApplicationJob
    queue_as :low

    # Never change this string. Solid Queue puts it in every lock key.
    CONCURRENCY_GROUP = "Catalog::SeatRefreshJob"

    # A run takes seconds. Two runs at once would only fetch the same counts twice.
    limits_concurrency to: 1, group: CONCURRENCY_GROUP, key: ->(*) { "seat_refresh" }, duration: 15.minutes

    ADD_DROP = 1.week

    def perform
      self.class.terms.each do |term|
        # Banner is not answering, and the next run is 30 minutes away. Stop
        # here instead of reporting a failure for each term that is left.
        break if BannerThrottle.cooldown_remaining

        changed = SeatRefresh.call(term)
        Rails.logger.info "[Catalog::SeatRefreshJob] #{term.name}: #{changed.inspect} sections changed"
      end
    end

    def self.terms
      Term.where(start_date: (Time.zone.today - ADD_DROP)..)
          .where(Course.where("courses.term_id = terms.id").arel.exists)
    end
  end
end

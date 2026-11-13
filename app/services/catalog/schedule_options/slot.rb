# frozen_string_literal: true

module Catalog
  module ScheduleOptions
    # One weekly meeting as plain values, so the search does not read Active
    # Record attributes in its inner loop. Catalog::ScheduleRules.overlap?
    # takes it the same as a Course::MeetingTime.
    Slot = Data.define(:day_of_week, :begin_time, :end_time, :start_date, :end_date) do
      def self.from(meeting_time)
        new(day_of_week: meeting_time.day_of_week, begin_time: meeting_time.begin_time, end_time: meeting_time.end_time,
            start_date: meeting_time.start_date, end_date: meeting_time.end_date)
      end
    end
  end
end

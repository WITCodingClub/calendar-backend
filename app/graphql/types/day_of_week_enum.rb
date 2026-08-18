# frozen_string_literal: true

module Types
  class DayOfWeekEnum < BaseEnum
    description "A day a section meets"

    Course::MeetingTime.day_of_weeks.each_key do |day|
      value day.upcase, day.capitalize, value: day
    end
  end
end

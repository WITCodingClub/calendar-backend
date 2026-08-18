# frozen_string_literal: true

module Types
  class ScheduleTypeEnum < BaseEnum
    description "How a section is delivered"

    Course::ScheduleType::TYPES.each do |key, config|
      value key.to_s.upcase, config[:readable_description], value: key.to_s
    end
  end
end

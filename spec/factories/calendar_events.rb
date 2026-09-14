# frozen_string_literal: true

FactoryBot.define do
  factory :calendar_event do
    # The model validates exactly one of meeting_time_id / final_exam_id /
    # university_calendar_event_id against the raw id column, so the
    # association has to be persisted even when this factory is built (not
    # created), or the foreign key stays nil and the validation fails.
    association :course_calendar, strategy: :create
    association :meeting_time, factory: :course_meeting_time, strategy: :create
    sequence(:external_event_id) { |n| "factory-evt-#{n}" }

    trait :for_final_exam do
      meeting_time { nil }
      association :final_exam, strategy: :create
    end

    trait :for_university_event do
      meeting_time { nil }
      association :university_calendar_event, strategy: :create
    end
  end
end

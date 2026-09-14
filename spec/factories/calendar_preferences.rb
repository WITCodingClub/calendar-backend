# frozen_string_literal: true

FactoryBot.define do
  factory :calendar_preference do
    association :user
    scope { :global }

    trait :for_event_type do
      scope { :event_type }
      event_type { "assignment" }
    end

    trait :uni_cal_global do
      scope { :uni_cal_global }
    end

    trait :uni_cal_category do
      scope { :uni_cal_category }
      event_type { "holiday" }
    end
  end
end

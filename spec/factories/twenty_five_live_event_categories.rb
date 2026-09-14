# frozen_string_literal: true

# twenty_five_live_id sequences start well above TwentyFiveLive::EventCategory::EVENT_CATEGORIES'
# highest seeded id (124), so factory rows never collide with real category ids.
FactoryBot.define do
  factory :twenty_five_live_event_category, class: "TwentyFiveLive::EventCategory" do
    sequence(:twenty_five_live_id) { |n| 900_000 + n }
    sequence(:name) { |n| "Factory Category #{n}" }
  end
end

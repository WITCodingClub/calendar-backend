# frozen_string_literal: true

# twenty_five_live_id sequences start well above the highest id seeded in
# TwentyFiveLive::EventCustomAttribute::EVENT_CUSTOM_ATTRIBUTES.
FactoryBot.define do
  factory :twenty_five_live_event_custom_attribute, class: "TwentyFiveLive::EventCustomAttribute" do
    sequence(:twenty_five_live_id) { |n| 900_000 + n }
    sequence(:name) { |n| "Factory Attribute #{n}" }
  end
end

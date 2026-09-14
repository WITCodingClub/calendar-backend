# frozen_string_literal: true

FactoryBot.define do
  factory :twenty_five_live_resource, class: "TwentyFiveLive::Resource" do
    sequence(:twenty_five_live_id) { |n| 900_000 + n }
    sequence(:name) { |n| "Factory Resource #{n}" }
  end
end

# frozen_string_literal: true

FactoryBot.define do
  factory :rmp_rating do
    association :faculty
    sequence(:rmp_id) { |n| "factory-rating-#{n}" }
  end
end

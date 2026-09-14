# frozen_string_literal: true

FactoryBot.define do
  factory :room do
    association :building
    sequence(:number) { |n| format("1%02d", n) }
  end
end

# frozen_string_literal: true

FactoryBot.define do
  factory :rating_distribution do
    association :faculty
    avg_rating { 4.0 }
    avg_difficulty { 2.5 }
    num_ratings { 10 }
    would_take_again_percent { 80.0 }
  end
end

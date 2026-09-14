# frozen_string_literal: true

FactoryBot.define do
  factory :term do
    sequence(:year) { |n| 2030 + n }
    season { :fall }
    uid { (year * 100) + Term.seasons.fetch(season.to_s) }
  end
end

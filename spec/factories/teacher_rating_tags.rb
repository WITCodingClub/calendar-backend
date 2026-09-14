# frozen_string_literal: true

FactoryBot.define do
  factory :teacher_rating_tag do
    association :faculty
    sequence(:rmp_legacy_id) { |n| n }
    tag_name { "Factory Tag" }
    tag_count { 0 }
  end
end

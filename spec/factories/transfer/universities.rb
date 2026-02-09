# frozen_string_literal: true

# == Schema Information
#
# Table name: transfer_universities
# Database name: primary
#
#  id         :bigint           not null, primary key
#  active     :boolean          default(TRUE), not null
#  code       :string           not null
#  country    :string
#  name       :string           not null
#  state      :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_transfer_universities_on_active  (active)
#  index_transfer_universities_on_code    (code) UNIQUE
#  index_transfer_universities_on_name    (name)
#
FactoryBot.define do
  factory :transfer_university, class: "Transfer::University" do
    sequence(:name) { |n| "University #{n}" }
    sequence(:code) { |n| "UNIV#{n.to_s.rjust(3, '0')}" }
    state { "MA" }
    country { "USA" }
    active { true }

    trait :inactive do
      active { false }
    end

    trait :international do
      state { nil }
      country { "Canada" }
    end

    trait :with_courses do
      after(:create) do |university|
        create_list(:transfer_course, 3, university: university)
      end
    end
  end
end

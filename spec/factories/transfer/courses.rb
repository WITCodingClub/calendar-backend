# frozen_string_literal: true

# == Schema Information
#
# Table name: transfer_courses
# Database name: primary
#
#  id            :bigint           not null, primary key
#  active        :boolean          default(TRUE), not null
#  course_code   :string           not null
#  course_title  :string           not null
#  credits       :decimal(5, 2)
#  description   :text
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  university_id :bigint           not null
#
# Indexes
#
#  index_transfer_courses_on_active                         (active)
#  index_transfer_courses_on_university_id                  (university_id)
#  index_transfer_courses_on_university_id_and_course_code  (university_id,course_code) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (university_id => transfer_universities.id)
#
FactoryBot.define do
  factory :transfer_course, class: "Transfer::Course" do
    university factory: %i[transfer_university]
    sequence(:course_code) { |n| "TRANS#{n.to_s.rjust(4, '0')}" }
    sequence(:course_title) { |n| "Transfer Course #{n}" }
    credits { 3.0 }
    description { "A course from a transfer institution" }
    active { true }

    trait :inactive do
      active { false }
    end

    trait :with_equivalencies do
      after(:create) do |course|
        create_list(:transfer_equivalency, 2, transfer_course: course)
      end
    end
  end
end

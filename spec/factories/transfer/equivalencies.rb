# frozen_string_literal: true

# == Schema Information
#
# Table name: transfer_equivalencies
# Database name: primary
#
#  id                 :bigint           not null, primary key
#  effective_date     :date             not null
#  expiration_date    :date
#  notes              :text
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  transfer_course_id :bigint           not null
#  wit_course_id      :bigint           not null
#
# Indexes
#
#  idx_transfer_equivalencies_unique                   (transfer_course_id,wit_course_id) UNIQUE
#  index_transfer_equivalencies_on_effective_date      (effective_date)
#  index_transfer_equivalencies_on_expiration_date     (expiration_date)
#  index_transfer_equivalencies_on_transfer_course_id  (transfer_course_id)
#  index_transfer_equivalencies_on_wit_course_id       (wit_course_id)
#
# Foreign Keys
#
#  fk_rails_...  (transfer_course_id => transfer_courses.id)
#  fk_rails_...  (wit_course_id => courses.id)
#
FactoryBot.define do
  factory :transfer_equivalency, class: "Transfer::Equivalency" do
    transfer_course
    wit_course factory: %i[course]
    effective_date { 1.year.ago }
    expiration_date { nil }
    notes { nil }

    trait :expired do
      expiration_date { 1.month.ago }
    end

    trait :expiring_soon do
      expiration_date { 1.month.from_now }
    end

    trait :with_notes do
      notes { "Special transfer equivalency with conditions" }
    end
  end
end

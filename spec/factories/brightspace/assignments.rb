# frozen_string_literal: true

# == Schema Information
#
# Table name: brightspace_assignments
#
#  id                 :bigint           not null, primary key
#  closes_at          :datetime
#  description        :text
#  due_at             :datetime
#  feedback           :text
#  kind               :string           not null
#  opens_at           :datetime
#  removed_at         :datetime
#  source_url         :string
#  submission_status  :string
#  submitted_at       :datetime
#  title              :string           not null
#  user_due_at        :datetime
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  course_offering_id :bigint           not null
#  source_id          :string           not null
#
# Indexes
#
#  index_brightspace_assignments_on_course_offering_id  (course_offering_id)
#  index_brightspace_assignments_on_source              (course_offering_id,kind,source_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (course_offering_id => brightspace_course_offerings.id)
#
FactoryBot.define do
  factory :brightspace_assignment, class: "Brightspace::Assignment" do
    association :course_offering, factory: :brightspace_course_offering
    kind { "assignment" }
    sequence(:source_id) { |n| (56_000 + n).to_s }
    title { "Lab #{Faker::Number.between(from: 1, to: 12)}" }
    due_at { 3.days.from_now.change(usec: 0) }

    trait :removed do
      removed_at { Time.current }
    end
  end
end

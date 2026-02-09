# frozen_string_literal: true

# == Schema Information
#
# Table name: course_plans
# Database name: primary
#
#  id                    :bigint           not null, primary key
#  notes                 :text
#  planned_course_number :integer          not null
#  planned_crn           :integer
#  planned_subject       :string           not null
#  status                :string           default("planned"), not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  course_id             :bigint
#  term_id               :bigint           not null
#  user_id               :bigint           not null
#
# Indexes
#
#  index_course_plans_on_course_id              (course_id)
#  index_course_plans_on_status                 (status)
#  index_course_plans_on_term_id                (term_id)
#  index_course_plans_on_user_id                (user_id)
#  index_course_plans_on_user_id_and_course_id  (user_id,course_id) UNIQUE WHERE (course_id IS NOT NULL)
#  index_course_plans_on_user_id_and_term_id    (user_id,term_id)
#
# Foreign Keys
#
#  fk_rails_...  (course_id => courses.id)
#  fk_rails_...  (term_id => terms.id)
#  fk_rails_...  (user_id => users.id)
#
FactoryBot.define do
  factory :course_plan do
    user
    term
    course { { optional: true } }
    planned_subject { "COMP" }
    planned_course_number { 2000 }
    planned_crn { nil }
    status { "planned" }
    notes { nil }

    trait :enrolled do
      status { "enrolled" }
      planned_crn { 12345 }
    end

    trait :completed do
      status { "completed" }
      planned_crn { 12345 }
    end

    trait :dropped do
      status { "dropped" }
      notes { "Dropped due to schedule conflict" }
    end

    trait :with_course do
      course
      after(:create) do |plan|
        plan.planned_subject = plan.course.subject
        plan.planned_course_number = plan.course.course_number
        plan.save
      end
    end
  end
end

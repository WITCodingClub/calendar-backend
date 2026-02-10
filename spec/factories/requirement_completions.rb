# frozen_string_literal: true

# == Schema Information
#
# Table name: requirement_completions
# Database name: primary
#
#  id                    :bigint           not null, primary key
#  completed_at          :datetime
#  course_number         :integer          not null
#  course_title          :string
#  credits               :decimal(5, 2)
#  grade                 :string
#  in_progress           :boolean          default(FALSE), not null
#  met_requirement       :boolean          default(FALSE), not null
#  source                :string           not null
#  subject               :string           not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  course_id             :bigint
#  degree_requirement_id :bigint           not null
#  term_id               :bigint
#  user_id               :bigint           not null
#
# Indexes
#
#  idx_on_user_id_degree_requirement_id_f4a11da44b         (user_id,degree_requirement_id)
#  index_requirement_completions_on_course_id              (course_id)
#  index_requirement_completions_on_degree_requirement_id  (degree_requirement_id)
#  index_requirement_completions_on_in_progress            (in_progress)
#  index_requirement_completions_on_source                 (source)
#  index_requirement_completions_on_term_id                (term_id)
#  index_requirement_completions_on_user_id                (user_id)
#  index_requirement_completions_on_user_id_and_course_id  (user_id,course_id) UNIQUE WHERE (course_id IS NOT NULL)
#
# Foreign Keys
#
#  fk_rails_...  (course_id => courses.id)
#  fk_rails_...  (degree_requirement_id => degree_requirements.id)
#  fk_rails_...  (term_id => terms.id)
#  fk_rails_...  (user_id => users.id)
#
FactoryBot.define do
  factory :requirement_completion do
    user
    degree_requirement
    course { { optional: true } }
    term { { optional: true } }
    subject { "COMP" }
    course_number { 1000 }
    course_title { "Introduction to Programming" }
    credits { 3.0 }
    grade { "A" }
    source { "wit" }
    completed_at { 1.year.ago }
    in_progress { false }
    met_requirement { true }

    trait :in_progress do
      in_progress { true }
      completed_at { nil }
      grade { nil }
    end

    trait :transfer_credit do
      source { "transfer" }
      course { nil }
      term { nil }
    end

    trait :failing_grade do
      grade { "F" }
      met_requirement { false }
    end

    trait :ap_credit do
      source { "ap" }
      grade { nil }
      course { nil }
      term { nil }
    end
  end
end

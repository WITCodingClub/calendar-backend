# frozen_string_literal: true

# == Schema Information
#
# Table name: course_outcomes
#
#  id         :bigint           not null, primary key
#  crn        :integer          not null
#  outcome    :string           not null
#  term_uid   :integer          not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_course_outcomes_on_user_id_and_term_uid_and_crn  (user_id,term_uid,crn) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
FactoryBot.define do
  factory :course_outcome do
    user
    term_uid { 202610 }
    sequence(:crn) { |n| 20_000 + n }
    outcome { "c_or_better" }

    # An outcome for a course and the term it belongs to.
    transient do
      course { nil }
    end

    after(:build) do |outcome, evaluator|
      next unless evaluator.course

      outcome.term_uid = evaluator.course.term.uid
      outcome.crn = evaluator.course.crn
    end
  end
end

# frozen_string_literal: true

# == Schema Information
#
# Table name: degree_evaluation_snapshots
# Database name: primary
#
#  id                      :bigint           not null, primary key
#  evaluated_at            :datetime         not null
#  evaluation_met          :boolean          default(FALSE), not null
#  minimum_gpa             :decimal(3, 2)
#  overall_gpa             :decimal(3, 2)
#  parsed_data             :jsonb
#  raw_html                :text
#  total_credits_completed :decimal(5, 2)
#  total_credits_required  :decimal(5, 2)
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  degree_program_id       :bigint           not null
#  evaluation_term_id      :bigint           not null
#  user_id                 :bigint           not null
#
# Indexes
#
#  idx_degree_eval_snapshots_unique                               (user_id,degree_program_id,evaluation_term_id) UNIQUE
#  index_degree_evaluation_snapshots_on_degree_program_id         (degree_program_id)
#  index_degree_evaluation_snapshots_on_evaluated_at              (evaluated_at)
#  index_degree_evaluation_snapshots_on_evaluation_term_id        (evaluation_term_id)
#  index_degree_evaluation_snapshots_on_user_id                   (user_id)
#  index_degree_evaluation_snapshots_on_user_id_and_evaluated_at  (user_id,evaluated_at)
#
# Foreign Keys
#
#  fk_rails_...  (degree_program_id => degree_programs.id)
#  fk_rails_...  (evaluation_term_id => terms.id)
#  fk_rails_...  (user_id => users.id)
#
FactoryBot.define do
  factory :degree_evaluation_snapshot do
    user
    degree_program
    evaluation_term factory: %i[term]
    evaluated_at { Time.current }
    total_credits_required { 120.0 }
    total_credits_completed { 90.0 }
    overall_gpa { 3.5 }
    minimum_gpa { 2.0 }
    evaluation_met { false }
    raw_html { "<html><body>Degree Evaluation Data</body></html>" }
    parsed_data { {} }

    trait :completed do
      total_credits_completed { 120.0 }
      evaluation_met { true }
    end

    trait :below_gpa do
      overall_gpa { 1.8 }
      minimum_gpa { 2.0 }
      evaluation_met { false }
    end

    trait :in_progress do
      total_credits_completed { 60.0 }
      evaluation_met { false }
    end
  end
end

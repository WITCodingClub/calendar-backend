# frozen_string_literal: true

# == Schema Information
#
# Table name: degree_evaluation_snapshots
# Database name: primary
#
#  id                      :bigint           not null, primary key
#  content_hash            :string
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
#  index_degree_evaluation_snapshots_on_content_hash              (content_hash)
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
class DegreeEvaluationSnapshot < ApplicationRecord
  belongs_to :user
  belongs_to :degree_program
  belongs_to :evaluation_term, class_name: "Term"

  validates :evaluated_at, presence: true
  validates :evaluation_term_id, uniqueness: { scope: [:user_id, :degree_program_id] }

  scope :most_recent, -> { order(evaluated_at: :desc) }
  scope :by_user, ->(user) { where(user: user) }
  scope :by_program, ->(program) { where(degree_program: program) }
  scope :evaluation_met, -> { where(evaluation_met: true) }
  include EncodedIds::HashidIdentifiable

  # Get the most recent snapshot for a user and program
  def self.latest_for_user_and_program(user, program)
    where(user: user, degree_program: program).order(evaluated_at: :desc).first
  end

  # Calculate progress percentage
  def progress_percentage
    return 0 if total_credits_required.nil? || total_credits_required.zero?

    ((total_credits_completed / total_credits_required) * 100).round(2)
  end

  # Check if GPA requirement is met
  def gpa_requirement_met?
    return true if minimum_gpa.nil?
    return false if overall_gpa.nil?

    overall_gpa >= minimum_gpa
  end

end

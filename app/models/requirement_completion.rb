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
class RequirementCompletion < ApplicationRecord
  include EncodedIds::HashidIdentifiable

  belongs_to :user
  belongs_to :degree_requirement
  belongs_to :course, optional: true
  belongs_to :term, optional: true

  validates :subject, presence: true
  validates :course_number, presence: true
  validates :source, presence: true
  validates :course_id, uniqueness: { scope: :user_id }, if: -> { course_id.present? }

  enum :source, {
    wit: "wit",
    transfer: "transfer",
    ap: "ap",
    clep: "clep",
    ib: "ib"
  }

  scope :completed, -> { where(in_progress: false) }
  scope :in_progress, -> { where(in_progress: true) }
  scope :by_user, ->(user) { where(user: user) }
  scope :by_requirement, ->(requirement) { where(degree_requirement: requirement) }
  scope :met, -> { where(met_requirement: true) }

  # Get course identifier string
  def course_identifier
    "#{subject} #{course_number}"
  end

  # Check if this completion has a passing grade
  def passing_grade?
    return true if grade.blank? # Some completions may not have grades yet

    # Common passing grades (can be customized based on institution)
    passing_grades = %w[A A- B+ B B- C+ C C- D+ D D- P S]
    passing_grades.include?(grade.upcase)
  end

end

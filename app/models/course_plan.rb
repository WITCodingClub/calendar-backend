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
class CoursePlan < ApplicationRecord
  belongs_to :user
  belongs_to :term
  belongs_to :course, optional: true

  validates :planned_subject, presence: true
  validates :planned_course_number, presence: true
  validates :status, presence: true
  validates :course_id, uniqueness: { scope: :user_id }, if: -> { course_id.present? }

  enum :status, {
    planned: "planned",
    enrolled: "enrolled",
    completed: "completed",
    dropped: "dropped",
    cancelled: "cancelled"
  }, default: :planned

  scope :active, -> { where(status: [:planned, :enrolled]) }
  scope :by_user, ->(user) { where(user: user) }
  scope :by_term, ->(term) { where(term: term) }
  scope :by_status, ->(status) { where(status: status) }

  # Get course identifier string
  def course_identifier
    "#{planned_subject} #{planned_course_number}"
  end

  # Get total credits for a user's plan in a term
  def self.total_credits_for_term(user, term)
    by_user(user)
      .by_term(term)
      .active
      .joins(:course)
      .sum("courses.credit_hours")
  end

  # Check if the course is actually enrolled (has a CRN)
  def enrolled?
    planned_crn.present? || status == "enrolled"
  end

end

# frozen_string_literal: true

# == Schema Information
#
# Table name: course_outcomes
#
#  id         :bigint           not null, primary key
#  outcome    :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  course_id  :bigint           not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_course_outcomes_on_course_id              (course_id)
#  index_course_outcomes_on_user_id_and_course_id  (user_id,course_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (course_id => courses.id) ON DELETE => cascade
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
# The result of one finished course for one student (#529). The extension
# converts the letter grade to an outcome, and the letter grade never reaches
# the backend.
#
# There are two pass values because some prerequisites need a C or higher,
# and a D still passes and gives credit.
class CourseOutcome < ApplicationRecord
  OUTCOMES = {
    c_or_better:    "c_or_better",
    passed_below_c: "passed_below_c",
    failed:         "failed",
    withdrawn:      "withdrawn",
    incomplete:     "incomplete"
  }.freeze

  enum :outcome, OUTCOMES, validate: true

  belongs_to :user
  belongs_to :course

  validates :course_id, uniqueness: { scope: :user_id }

  def passed? = c_or_better? || passed_below_c?
end

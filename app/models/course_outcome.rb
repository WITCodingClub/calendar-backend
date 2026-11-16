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
# The result of one finished course for one student (#529). The extension
# converts the letter grade to an outcome, and the letter grade never reaches
# the backend.
#
# There are two pass values because some prerequisites need a C or higher,
# and a D still passes and gives credit.
#
# A row names its course by term code and CRN, not by course id, so it stays
# when Courses::Reprocessor or `rake catalog:refresh` makes the course or the
# enrollment again.
class CourseOutcome < ApplicationRecord
  OUTCOMES = {
    c_or_better:    "c_or_better",
    passed_below_c: "passed_below_c",
    failed:         "failed",
    withdrawn:      "withdrawn",
    incomplete:     "incomplete"
  }.freeze
  PASSED_BELOW_C = OUTCOMES[:passed_below_c]
  # A D passes and gives credit, but does not meet a minimum grade of C.
  PASSED = [ OUTCOMES[:c_or_better], PASSED_BELOW_C ].freeze

  enum :outcome, OUTCOMES, validate: true

  belongs_to :user

  validates :term_uid, :crn, presence: true
  validates :crn, uniqueness: { scope: %i[user_id term_uid] }
end

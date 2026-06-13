# frozen_string_literal: true

class Enrollment < ApplicationRecord
  belongs_to :user
  belongs_to :course
  belongs_to :term

  validates :user_id, uniqueness: { scope: [:course_id, :term_id], message: "is already enrolled in this course for this term" }
end

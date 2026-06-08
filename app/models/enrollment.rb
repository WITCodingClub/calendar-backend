# frozen_string_literal: true

class Enrollment < ApplicationRecord
  belongs_to :user
  belongs_to :course

  validates :user_id, uniqueness: { scope: :course_id, message: "is already enrolled in this course" }
end

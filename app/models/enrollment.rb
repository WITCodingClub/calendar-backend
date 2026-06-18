# frozen_string_literal: true

# == Schema Information
#
# Table name: enrollments
#
#  id         :bigint           not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  course_id  :bigint           not null
#  term_id    :bigint           not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_enrollments_on_course_id        (course_id)
#  index_enrollments_on_term_id          (term_id)
#  index_enrollments_on_user_class_term  (user_id,course_id,term_id) UNIQUE
#  index_enrollments_on_user_id          (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (course_id => courses.id)
#  fk_rails_...  (term_id => terms.id)
#  fk_rails_...  (user_id => users.id)
#
class Enrollment < ApplicationRecord
  belongs_to :user
  belongs_to :course
  belongs_to :term

  validates :user_id, uniqueness: { scope: [ :course_id, :term_id ], message: "is already enrolled in this course for this term" }
end

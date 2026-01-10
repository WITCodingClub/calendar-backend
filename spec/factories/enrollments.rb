# frozen_string_literal: true

# == Schema Information
#
# Table name: enrollments
# Database name: primary
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
FactoryBot.define do
  factory :enrollment do
    user

    # Allow course to be passed in, defaulting to a new course
    transient do
      provided_course { nil }
    end

    # If a course is provided, use its term; otherwise create a fresh term and course
    term { provided_course&.term || association(:term) }
    course { provided_course || association(:course, term: term) }

    # Override to handle explicit course assignment via attributes
    after(:build) do |enrollment, evaluator|
      # If course was set directly (not via transient), ensure term matches
      if enrollment.course&.term && enrollment.term != enrollment.course.term
        enrollment.term = enrollment.course.term
      end
    end
  end
end

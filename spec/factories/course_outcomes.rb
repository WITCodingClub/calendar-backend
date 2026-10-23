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
FactoryBot.define do
  factory :course_outcome do
    user
    course
    outcome { "c_or_better" }
  end
end

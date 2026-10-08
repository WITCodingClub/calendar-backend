# frozen_string_literal: true

# == Schema Information
#
# Table name: brightspace_assignment_preferences
#
#  id              :bigint           not null, primary key
#  due_at_override :datetime
#  progress        :string           default("not_started"), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  assignment_id   :bigint           not null
#  user_id         :bigint           not null
#
# Indexes
#
#  index_brightspace_assignment_preferences_on_assignment_id  (assignment_id) UNIQUE
#  index_brightspace_assignment_preferences_on_user_id        (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (assignment_id => brightspace_assignments.id)
#  fk_rails_...  (user_id => users.id)
#
FactoryBot.define do
  factory :brightspace_assignment_preference, class: "Brightspace::AssignmentPreference" do
    association :assignment, factory: :brightspace_assignment
    user { assignment.course_offering.connection.user }
    progress { "in_progress" }
  end
end

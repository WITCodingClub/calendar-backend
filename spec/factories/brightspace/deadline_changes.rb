# frozen_string_literal: true

# == Schema Information
#
# Table name: brightspace_deadline_changes
#
#  id            :bigint           not null, primary key
#  current_at    :datetime
#  detected_at   :datetime         not null
#  field         :string           not null
#  notified_at   :datetime
#  previous_at   :datetime
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  assignment_id :bigint           not null
#
# Indexes
#
#  index_brightspace_deadline_changes_on_assignment_id  (assignment_id)
#  index_brightspace_deadline_changes_unnotified        (notified_at) WHERE (notified_at IS NULL)
#
# Foreign Keys
#
#  fk_rails_...  (assignment_id => brightspace_assignments.id)
#
FactoryBot.define do
  factory :brightspace_deadline_change, class: "Brightspace::DeadlineChange" do
    association :assignment, factory: :brightspace_assignment
    field { "due_at" }
    previous_at { 1.day.from_now.change(usec: 0) }
    current_at { 2.days.from_now.change(usec: 0) }
    detected_at { Time.current }
  end
end

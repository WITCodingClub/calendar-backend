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
module Brightspace
  # The user's progress and personal deadline. Without a row, the defaults.
  class AssignmentPreferenceSerializer
    def initialize(preference)
      @preference = preference
    end

    def as_json(*)
      {
        progress:        @preference&.progress || "not_started",
        due_at_override: @preference&.due_at_override&.utc&.iso8601
      }
    end
  end
end

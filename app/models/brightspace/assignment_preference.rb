# frozen_string_literal: true

# The user's own progress on an assignment and a personal deadline. "done"
# never changes the Brightspace submission status.
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
  class AssignmentPreference < ApplicationRecord
    include EncodedIds::HashidIdentifiable
    include Brightspace::VersionBumping

    set_public_id_prefix :bap, min_hash_length: 12

    PROGRESSES = %w[not_started in_progress done].freeze

    belongs_to :user
    belongs_to :assignment, class_name: "Brightspace::Assignment", inverse_of: :preference

    validates :progress, inclusion: { in: PROGRESSES }
    validates :assignment_id, uniqueness: true
    validate :assignment_belongs_to_user

    delegate :course_offering, to: :assignment

    private

    # The owner of the row must own the assignment. No matcher covers a check
    # across two associations.
    def assignment_belongs_to_user
      return if assignment.nil? || user.nil?

      errors.add(:assignment, "is not one of your assignments") unless assignment.course_offering.connection.user_id == user_id
    end
  end
end

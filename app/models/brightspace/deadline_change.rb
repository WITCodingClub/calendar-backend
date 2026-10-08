# frozen_string_literal: true

# A deadline that changed between two syncs. notified_at stays nil until a
# notification goes out, so a notifier can find the pending changes.
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
module Brightspace
  class DeadlineChange < ApplicationRecord
    include EncodedIds::HashidIdentifiable

    set_public_id_prefix :bdc, min_hash_length: 12

    FIELDS = %w[due_at user_due_at opens_at closes_at].freeze

    belongs_to :assignment, class_name: "Brightspace::Assignment", inverse_of: :deadline_changes

    validates :field, inclusion: { in: FIELDS }
    validates :detected_at, presence: true

    scope :pending_notification, -> { where(notified_at: nil) }
  end
end

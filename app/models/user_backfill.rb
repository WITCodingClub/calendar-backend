# frozen_string_literal: true

# A one-time catch-up run that the extension finished for one student
# (WITCodingClub/calendar-extension#215). The extension reads the list on
# panel load, starts each run that has no row, and marks it done only after
# the run finishes. A run that fails has no row, so the next panel load tries
# again.
# == Schema Information
#
# Table name: user_backfills
#
#  id           :bigint           not null, primary key
#  completed_at :datetime         not null
#  name         :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  user_id      :bigint           not null
#
# Indexes
#
#  index_user_backfills_on_user_id_and_name  (user_id,name) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
class UserBackfill < ApplicationRecord
  NAMES = {
    # Every past LeopardWeb term, processed for a student who upgraded to v6.
    past_terms:    "past_terms",
    # The academic profile and the course outcomes from LeopardWeb (#529).
    academic_data: "academic_data"
  }.freeze

  enum :name, NAMES, validate: true

  belongs_to :user

  validates :completed_at, presence: true
  validates :name, uniqueness: { scope: :user_id }

  # Marks the run done now. One upsert, so two extension windows that finish
  # at the same time never collide on the unique index.
  def self.complete!(user, name)
    upsert({ user_id: user.id, name: name, completed_at: Time.current }, unique_by: %i[user_id name], record_timestamps: true) # rubocop:disable Rails/SkipsModelValidations
  end
end

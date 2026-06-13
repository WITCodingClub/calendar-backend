# frozen_string_literal: true

# == Schema Information
#
# Table name: enrollment_snapshots
#
#  id                  :bigint           not null, primary key
#  course_number       :integer
#  credit_hours        :integer
#  crn                 :integer          not null
#  faculty_data        :jsonb
#  schedule_type       :string
#  section_number      :string
#  snapshot_created_at :datetime         not null
#  snapshot_reason     :string
#  subject             :string
#  title               :string
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  term_id             :bigint           not null
#  user_id             :bigint           not null
#
# Indexes
#
#  idx_enrollment_snapshots_unique                    (user_id,term_id,crn) UNIQUE
#  index_enrollment_snapshots_on_crn                  (crn)
#  index_enrollment_snapshots_on_snapshot_created_at  (snapshot_created_at)
#  index_enrollment_snapshots_on_term_id              (term_id)
#  index_enrollment_snapshots_on_user_id              (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (term_id => terms.id)
#  fk_rails_...  (user_id => users.id)
#
class EnrollmentSnapshot < ApplicationRecord
  belongs_to :user
  belongs_to :term

  validates :crn, presence: true

  scope :for_term,   ->(term) { where(term: term) }
  scope :for_user,   ->(user) { where(user: user) }
  scope :recent,     -> { order(snapshot_created_at: :desc) }
end

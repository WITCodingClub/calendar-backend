# frozen_string_literal: true

class EnrollmentSnapshot < ApplicationRecord
  belongs_to :user
  belongs_to :term

  validates :crn, presence: true

  scope :for_term,   ->(term) { where(term: term) }
  scope :for_user,   ->(user) { where(user: user) }
  scope :recent,     -> { order(snapshot_created_at: :desc) }
end

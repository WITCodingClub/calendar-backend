# frozen_string_literal: true

# == Schema Information
#
# Table name: transfer_equivalencies
# Database name: primary
#
#  id                 :bigint           not null, primary key
#  effective_date     :date             not null
#  expiration_date    :date
#  notes              :text
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  transfer_course_id :bigint           not null
#  wit_course_id      :bigint           not null
#
# Indexes
#
#  idx_transfer_equivalencies_unique                   (transfer_course_id,wit_course_id) UNIQUE
#  index_transfer_equivalencies_on_effective_date      (effective_date)
#  index_transfer_equivalencies_on_expiration_date     (expiration_date)
#  index_transfer_equivalencies_on_transfer_course_id  (transfer_course_id)
#  index_transfer_equivalencies_on_wit_course_id       (wit_course_id)
#
# Foreign Keys
#
#  fk_rails_...  (transfer_course_id => transfer_courses.id)
#  fk_rails_...  (wit_course_id => courses.id)
#
module Transfer
  class Equivalency < ApplicationRecord
    self.table_name = "transfer_equivalencies"

    belongs_to :transfer_course, class_name: "Transfer::Course"
    belongs_to :wit_course, class_name: "Course"

    validates :effective_date, presence: true
    validates :wit_course_id, uniqueness: { scope: :transfer_course_id }
    validate :expiration_after_effective

    scope :active, -> { where("expiration_date IS NULL OR expiration_date > ?", Date.current) }
    scope :expired, -> { where("expiration_date IS NOT NULL AND expiration_date <= ?", Date.current) }
    scope :effective_on, ->(date) { where(effective_date: ..date) }

    # Check if this equivalency is currently active
    def active?
      return true if expiration_date.nil?

      expiration_date > Date.current
    end

    # Check if this equivalency has expired
    def expired?
      !active?
    end

    private

    def expiration_after_effective
      return if expiration_date.nil?
      return if effective_date.nil?

      return unless expiration_date <= effective_date

      errors.add(:expiration_date, "must be after effective date")

    end

  end
end

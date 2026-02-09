# frozen_string_literal: true

# == Schema Information
#
# Table name: transfer_universities
# Database name: primary
#
#  id         :bigint           not null, primary key
#  active     :boolean          default(TRUE), not null
#  code       :string           not null
#  country    :string
#  name       :string           not null
#  state      :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_transfer_universities_on_active  (active)
#  index_transfer_universities_on_code    (code) UNIQUE
#  index_transfer_universities_on_name    (name)
#
module Transfer
  class University < ApplicationRecord
    self.table_name = "transfer_universities"

    include EncodedIds::HashidIdentifiable

    set_public_id_prefix :tru

    has_many :transfer_courses, class_name: "Transfer::Course", dependent: :destroy

    validates :name, presence: true
    validates :code, presence: true, uniqueness: true

    scope :active, -> { where(active: true) }
    scope :by_state, ->(state) { where(state: state) }
    scope :by_country, ->(country) { where(country: country) }

    # Get all equivalencies through courses
    def equivalencies
      Transfer::Equivalency.joins(:transfer_course).where(transfer_courses: { university_id: id })
    end

  end
end

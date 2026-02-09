# frozen_string_literal: true

# == Schema Information
#
# Table name: transfer_courses
# Database name: primary
#
#  id            :bigint           not null, primary key
#  active        :boolean          default(TRUE), not null
#  course_code   :string           not null
#  course_title  :string           not null
#  credits       :decimal(5, 2)
#  description   :text
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  university_id :bigint           not null
#
# Indexes
#
#  index_transfer_courses_on_active                         (active)
#  index_transfer_courses_on_university_id                  (university_id)
#  index_transfer_courses_on_university_id_and_course_code  (university_id,course_code) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (university_id => transfer_universities.id)
#
module Transfer
  class Course < ApplicationRecord
    self.table_name = "transfer_courses"

    include EncodedIds::HashidIdentifiable

    set_public_id_prefix :trc

    belongs_to :university, class_name: "Transfer::University"
    has_many :transfer_equivalencies, class_name: "Transfer::Equivalency", foreign_key: "transfer_course_id", dependent: :destroy, inverse_of: :transfer_course
    has_many :wit_courses, through: :transfer_equivalencies, source: :wit_course

    validates :course_code, presence: true
    validates :course_title, presence: true
    validates :course_code, uniqueness: { scope: :university_id }

    scope :active, -> { where(active: true) }
    scope :by_university, ->(university) { where(university: university) }

    # Get course identifier string
    def course_identifier
      "#{course_code} - #{course_title}"
    end

    # Check if this course has active equivalencies
    def has_equivalencies?
      transfer_equivalencies.any?
    end

  end
end

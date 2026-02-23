# frozen_string_literal: true

# == Schema Information
#
# Table name: course_prerequisites
# Database name: primary
#
#  id                 :bigint           not null, primary key
#  min_grade          :string
#  prerequisite_logic :string
#  prerequisite_rule  :text             not null
#  prerequisite_type  :string           not null
#  waivable           :boolean          default(FALSE), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  course_id          :bigint           not null
#
# Indexes
#
#  index_course_prerequisites_on_course_id                        (course_id)
#  index_course_prerequisites_on_course_id_and_prerequisite_type  (course_id,prerequisite_type)
#  index_course_prerequisites_on_prerequisite_type                (prerequisite_type)
#
# Foreign Keys
#
#  fk_rails_...  (course_id => courses.id)
#
class CoursePrerequisite < ApplicationRecord
  belongs_to :course

  validates :prerequisite_type, presence: true
  validates :prerequisite_rule, presence: true

  enum :prerequisite_type, {
    prerequisite: "prerequisite",
    corequisite: "corequisite",
    recommended: "recommended"
  }

  scope :by_type, ->(type) { where(prerequisite_type: type) }
  scope :required, -> { where(prerequisite_type: [:prerequisite, :corequisite]) }
  scope :waivable_only, -> { where(waivable: true) }

  # Parse prerequisite rule to extract course requirements
  # This is a simple implementation - the actual parser will be in PrerequisiteParserService
  def extract_course_codes
    # Example: "COMP1000 and MATH2300" -> ["COMP1000", "MATH2300"]
    prerequisite_rule.scan(/[A-Z]{3,4}\d{4}/)
  end

end

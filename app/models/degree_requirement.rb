# frozen_string_literal: true

# == Schema Information
#
# Table name: degree_requirements
# Database name: primary
#
#  id                    :bigint           not null, primary key
#  area_name             :string           not null
#  course_choice_logic   :string
#  course_number         :integer
#  courses_required      :integer
#  credits_required      :decimal(5, 2)
#  requirement_name      :string           not null
#  requirement_type      :string           not null
#  rule_text             :text
#  subject               :string
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  degree_program_id     :bigint           not null
#  parent_requirement_id :bigint
#
# Indexes
#
#  index_degree_requirements_on_degree_program_id                (degree_program_id)
#  index_degree_requirements_on_degree_program_id_and_area_name  (degree_program_id,area_name)
#  index_degree_requirements_on_parent_requirement_id            (parent_requirement_id)
#  index_degree_requirements_on_requirement_type                 (requirement_type)
#
# Foreign Keys
#
#  fk_rails_...  (degree_program_id => degree_programs.id)
#  fk_rails_...  (parent_requirement_id => degree_requirements.id)
#
class DegreeRequirement < ApplicationRecord
  belongs_to :degree_program
  belongs_to :parent_requirement, class_name: "DegreeRequirement", optional: true, inverse_of: :child_requirements
  has_many :child_requirements, class_name: "DegreeRequirement", foreign_key: "parent_requirement_id", dependent: :destroy, inverse_of: :parent_requirement
  has_many :requirement_completions, dependent: :destroy

  validates :area_name, presence: true
  validates :requirement_name, presence: true
  validates :requirement_type, presence: true
  include EncodedIds::HashidIdentifiable

  enum :requirement_type, {
    core: "core",
    major: "major",
    minor: "minor",
    elective: "elective",
    general_education: "general_education",
    concentration: "concentration"
  }

  scope :by_area, ->(area) { where(area_name: area) }
  scope :by_type, ->(type) { where(requirement_type: type) }
  scope :root_requirements, -> { where(parent_requirement_id: nil) }
  scope :child_requirements_of, ->(parent) { where(parent_requirement: parent) }

  # Check if this requirement specifies a specific course
  def specific_course?
    subject.present? && course_number.present?
  end

  # Get full course identifier if specific course
  def course_identifier
    return nil unless specific_course?

    "#{subject} #{course_number}"
  end

end

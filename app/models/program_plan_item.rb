# frozen_string_literal: true

# One row of a plan of study: what a student takes in one semester.
# year_index is the year of the plan (1 is the first year), and season is
# the semester in that year.
#
# kind says what the row names:
#   course       one course, by subject_code and course_number
#   placeholder  a slot such as "Computer Science Elective". elective_group
#                is the list it draws from, when the page has one.
#   choice       one course from options, such as COMP1000 or COMP1099:
#                [{ "subject_code" => "COMP", "course_number" => 1000 }, ...]
#
# Credits are a range for a row such as "3-4 credits". lecture_hours and
# lab_hours are only in the PDF catalogs.
# == Schema Information
#
# Table name: program_plan_items
#
#  id                :bigint           not null, primary key
#  course_number     :integer
#  footnote          :string
#  kind              :string           not null
#  lab_hours         :integer
#  label             :string
#  lecture_hours     :integer
#  max_credits       :integer
#  min_credits       :integer
#  options           :jsonb            not null
#  position          :integer          not null
#  season            :string           not null
#  subject_code      :string
#  year_index        :integer          not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  catalog_course_id :bigint
#  elective_group_id :bigint
#  program_plan_id   :bigint           not null
#
# Indexes
#
#  index_program_plan_items_on_catalog_course_id               (catalog_course_id)
#  index_program_plan_items_on_elective_group_id               (elective_group_id)
#  index_program_plan_items_on_program_plan_id_and_position    (program_plan_id,position) UNIQUE
#  index_program_plan_items_on_subject_code_and_course_number  (subject_code,course_number)
#
# Foreign Keys
#
#  fk_rails_...  (catalog_course_id => catalog_courses.id) ON DELETE => nullify
#  fk_rails_...  (elective_group_id => elective_groups.id) ON DELETE => nullify
#  fk_rails_...  (program_plan_id => program_plans.id) ON DELETE => cascade
#
class ProgramPlanItem < ApplicationRecord
  include CatalogCourseLinkable

  SEASONS = { fall: "fall", spring: "spring", summer: "summer" }.freeze
  KINDS = { course: "course", placeholder: "placeholder", choice: "choice" }.freeze

  enum :season, SEASONS, validate: true
  enum :kind, KINDS, validate: true

  belongs_to :program_plan
  belongs_to :elective_group, optional: true

  validates :year_index, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validates :position, presence: true, uniqueness: { scope: :program_plan_id }
  validates :subject_code, :course_number, presence: true, if: :course?
  validates :label, presence: true, if: :placeholder?
  validate :options_name_courses, if: :choice?

  private

  def options_name_courses
    valid = options.is_a?(Array) && options.size >= 2 &&
            options.all? { |option| option.is_a?(Hash) && option["subject_code"].present? && option["course_number"].present? }
    errors.add(:options, "must list at least two courses") unless valid
  end
end

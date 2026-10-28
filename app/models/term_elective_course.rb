# frozen_string_literal: true

# One course code in a term elective list. heading is the nearest heading
# above the code in the PDF, such as "Computer Science Elective" or "Social
# Science". It is nil when the PDF has no heading above the code.
# == Schema Information
#
# Table name: term_elective_courses
#
#  id                    :bigint           not null, primary key
#  course_number         :integer          not null
#  heading               :text
#  position              :integer          default(0), not null
#  subject_code          :string           not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  catalog_course_id     :bigint
#  term_elective_list_id :bigint           not null
#
# Indexes
#
#  idx_term_elective_courses_unique                               (term_elective_list_id,subject_code,course_number,heading) UNIQUE NULLS NOT DISTINCT
#  index_term_elective_courses_on_catalog_course_id               (catalog_course_id)
#  index_term_elective_courses_on_subject_code_and_course_number  (subject_code,course_number)
#
# Foreign Keys
#
#  fk_rails_...  (catalog_course_id => catalog_courses.id) ON DELETE => nullify
#  fk_rails_...  (term_elective_list_id => term_elective_lists.id) ON DELETE => cascade
#
class TermElectiveCourse < ApplicationRecord
  include CatalogCourseLinkable

  belongs_to :term_elective_list

  validates :subject_code, :course_number, presence: true
  validates :course_number, uniqueness: { scope: [ :term_elective_list_id, :subject_code, :heading ] }
end

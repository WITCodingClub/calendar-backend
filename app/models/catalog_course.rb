# frozen_string_literal: true

# One course, such as COMP 2350, across every term. Course rows are sections in
# one term. This row holds what Banner says about the course itself: the
# description, prerequisites, corequisites, restrictions, and the terms it is
# usually offered. Catalog::CourseDetailsSync writes it.
#
# prerequisites is a tree (Catalog::CourseDetailsParser):
#   { "type" => "and" | "or", "operands" => [...] }
#   { "type" => "course", "subject_code" => "COMP", "course_number" => 1050, "min_grade" => "C", "level" => "Undergraduate" }
#   { "type" => "test", "name" => "WIT Math Assessment", "score" => "1500" }
class CatalogCourse < ApplicationRecord
  CODE_PATTERN = /\A\s*([A-Za-z]{2,5})\s*-?\s*(\d{3,4})\s*\z/

  belongs_to :source_term, class_name: "Term", optional: true

  has_many :course_prerequisites, dependent: :delete_all
  has_many :prerequisite_courses, through: :course_prerequisites, source: :required_catalog_course
  # The prerequisite rows of other courses that name this one.
  has_many :required_by, class_name: "CoursePrerequisite", foreign_key: :required_catalog_course_id,
                         inverse_of: :required_catalog_course, dependent: :nullify
  has_many :unlocks, through: :required_by, source: :catalog_course

  validates :subject_code, :course_number, presence: true
  validates :course_number, uniqueness: { scope: :subject_code }

  before_validation { self.subject_code = subject_code&.strip&.upcase }

  # "COMP2350", "COMP 2350", or "comp-2350" to ["COMP", 2350], or nil.
  def self.parse_code(code)
    match = CODE_PATTERN.match(code.to_s)
    match && [ match[1].upcase, match[2].to_i ]
  end

  def self.find_by_code(code)
    subject_code, course_number = parse_code(code)
    subject_code && find_by(subject_code: subject_code, course_number: course_number)
  end

  def code = "#{subject_code} #{course_number}"

  # The sections of this course in one term.
  def sections_in(term)
    Catalog::SectionQuery.new.call(term_uid: term.uid, subject: [ subject_code ], course_number: [ course_number ])
  end
end

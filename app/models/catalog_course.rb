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
# == Schema Information
#
# Table name: catalog_courses
#
#  id                  :bigint           not null, primary key
#  college             :string
#  corequisites        :jsonb            not null
#  course_number       :integer          not null
#  credit_hours        :integer
#  department          :string
#  description         :text
#  details_fetched_at  :datetime
#  division            :string
#  embedding           :vector(1536)
#  embedding_digest    :string(64)
#  fees                :jsonb            not null
#  grading_modes       :string           default([]), not null, is an Array
#  learning_objectives :text
#  levels              :string           default([]), not null, is an Array
#  mutual_exclusions   :jsonb            not null
#  prerequisites       :jsonb
#  restrictions        :jsonb            not null
#  subject_code        :string           not null
#  title               :string
#  typically_offered   :string           default([]), not null, is an Array
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  source_term_id      :bigint
#
# Indexes
#
#  index_catalog_courses_on_embedding                       (embedding vector_cosine_ops) USING hnsw
#  index_catalog_courses_on_source_term_id                  (source_term_id)
#  index_catalog_courses_on_subject_code_and_course_number  (subject_code,course_number) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (source_term_id => terms.id)
#
class CatalogCourse < ApplicationRecord
  include Embeddable

  CODE_PATTERN = /\A\s*([A-Za-z]{2,5})\s*-?\s*(\d{3,4})\s*\z/

  # Learning objectives can run to several pages. The vector keeps the start,
  # so the objectives add meaning without drowning out the title.
  OBJECTIVES_LIMIT = 1_000

  belongs_to :source_term, class_name: "Term", optional: true

  has_many :course_prerequisites, dependent: :delete_all
  has_many :prerequisite_courses, through: :course_prerequisites, source: :required_catalog_course
  # The prerequisite rows of other courses that name this one.
  has_many :required_by, class_name: "CoursePrerequisite", foreign_key: :required_catalog_course_id,
                         inverse_of: :required_catalog_course, dependent: :nullify
  has_many :unlocks, through: :required_by, source: :catalog_course
  # The catalog rows that name this course (CatalogCourseLinkable).
  has_many :catalog_year_courses, dependent: :nullify
  has_many :program_plan_items, dependent: :nullify
  has_many :elective_group_courses, dependent: :nullify

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

  # What the course teaches, in the words a student would search with. One
  # vector stands for every section of the course (docs/embeddings.md).
  #
  # Banner's description wins. A course that Banner has not described yet
  # takes the description from its newest catalog year. Offerings, fees and
  # prerequisites stay out: filters answer those, and they say nothing about
  # what the course is about.
  def embedding_text
    [
      [ code, title.presence || newest_catalog_entry&.title ].compact_blank.join(" "),
      description.presence || newest_catalog_entry&.description,
      learning_objectives&.squish&.truncate(OBJECTIVES_LIMIT, separator: " ", omission: ""),
      department,
      college
    ].compact_blank.join("\n")
  end

  # The entry from the newest catalog year that lists this course.
  def newest_catalog_entry
    catalog_year_courses.max_by { |entry| entry.catalog_year.start_year }
  end

  # The sections of this course in one term.
  def sections_in(term)
    Catalog::SectionQuery.new.call(term_uid: term.uid, subject: [ subject_code ], course_number: [ course_number ])
  end
end

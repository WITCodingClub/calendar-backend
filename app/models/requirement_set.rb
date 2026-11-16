# frozen_string_literal: true

# What one program requires in one catalog year: its plans of study and the
# elective lists they name. name, school_name, and department_name are as
# the catalog printed them that year, because they change between years.
#
# needs_review is set for a set read from a PDF, until a person checks it.
# source_digest lets the import skip a page that did not change, and
# last_seen_at shows a program that the current catalog no longer lists.
# == Schema Information
#
# Table name: requirement_sets
#
#  id                :bigint           not null, primary key
#  department_name   :string
#  description       :text
#  fetched_at        :datetime
#  hss_requirement   :jsonb
#  last_seen_at      :datetime
#  name              :string           not null
#  needs_review      :boolean          default(FALSE), not null
#  path              :string
#  reviewed_at       :datetime
#  school_name       :string
#  source            :string           default("html"), not null
#  source_digest     :string
#  total_credits     :integer
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  catalog_year_id   :bigint           not null
#  degree_program_id :bigint           not null
#
# Indexes
#
#  idx_on_degree_program_id_catalog_year_id_10cd4884bd  (degree_program_id,catalog_year_id) UNIQUE
#  index_requirement_sets_on_catalog_year_id            (catalog_year_id)
#
# Foreign Keys
#
#  fk_rails_...  (catalog_year_id => catalog_years.id)
#  fk_rails_...  (degree_program_id => degree_programs.id)
#
class RequirementSet < ApplicationRecord
  SOURCES = CatalogYear::SOURCES

  enum :source, SOURCES, validate: true, prefix: true

  belongs_to :degree_program
  belongs_to :catalog_year

  has_many :program_plans, -> { order(:position) }, dependent: :delete_all, inverse_of: :requirement_set
  has_many :elective_groups, -> { order(:position) }, dependent: :delete_all, inverse_of: :requirement_set

  validates :name, presence: true
  validates :degree_program_id, uniqueness: { scope: :catalog_year_id }

  # A set with its plans, plan items, and lists, as the program API and
  # degree planning read it.
  scope :with_requirements, lambda {
    includes(:catalog_year, degree_program: :parent_program,
             program_plans: { items: :elective_group }, elective_groups: %i[courses program_plan])
  }

  # The set of each program row (StudentProgram) that links to one, keyed by
  # [degree_program_id, catalog_year_id], in one query.
  def self.index_for(programs)
    linked = programs.select { |program| program.degree_program_id && program.catalog_year_id }
    return {} if linked.empty?

    where(degree_program_id: linked.map(&:degree_program_id).uniq, catalog_year_id: linked.map(&:catalog_year_id).uniq)
      .index_by { |set| [ set.degree_program_id, set.catalog_year_id ] }
  end

  # The plan to use when a student has not said which plan they follow: the
  # first plan that is not accelerated, such as the four-year plan. It reads
  # the loaded plans, so a caller that preloads them sends no query.
  def standard_plan
    plans = program_plans.to_a
    plans.find { |plan| !plan.accelerated } || plans.first
  end

  # The plan with this name, case ignored, or nil.
  def plan_named(name) = program_plans.to_a.find { |plan| plan.name.casecmp?(name.to_s.strip) }

  # The last import of a catalog year saw every set whose last_seen_at is
  # after this time. A set seen before it is of a program that left the
  # catalog.
  def self.listed_since(catalog_year)
    catalog_year.imported_at - 1.day
  end

  # The sets of a program that the last import of its catalog year saw.
  def self.listed_in(catalog_year)
    catalog_year.imported_at ? where(last_seen_at: listed_since(catalog_year)..) : all
  end

  def listed?
    catalog_year.imported_at.nil? || (last_seen_at.present? && last_seen_at >= self.class.listed_since(catalog_year))
  end
end

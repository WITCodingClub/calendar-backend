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
#  last_seen_at      :datetime
#  name              :string           not null
#  needs_review      :boolean          default(FALSE), not null
#  path              :string
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

  # The plan to use when a student has not said which plan they follow: the
  # first plan that is not accelerated, such as the four-year plan.
  def standard_plan
    program_plans.where(accelerated: false).first || program_plans.first
  end

  # The program page this set came from. A set from the Wayback Machine
  # links to the capture, because the catalog site has no copy of that year.
  def catalog_url
    return nil if path.blank?

    url = "#{DegreeRequirements::SITE_URL}#{path}"
    timestamp = DegreeRequirements::WAYBACK_TIMESTAMPS[catalog_year.start_year]
    source_wayback? && timestamp ? "https://web.archive.org/web/#{timestamp}/#{url}" : url
  end
end

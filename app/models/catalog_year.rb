# frozen_string_literal: true

# One edition of the academic catalog at catalog.wit.edu, such as 2024-2025.
# start_year is the first year: 2024 for 2024-2025. A student follows the
# catalog of the term they started a program in (docs/degree-requirements.md).
#
# `source` says where the import read the catalog: the CourseLeaf site
# (`html`), a Wayback Machine copy (`wayback`, 2025-2026 has no archive), or
# the PDF (`pdf`, before 2019-2020). `status` is `missing` when the catalog
# was not published when the import looked for it.
# == Schema Information
#
# Table name: catalog_years
#
#  id          :bigint           not null, primary key
#  base_url    :string
#  imported_at :datetime
#  source      :string           default("html"), not null
#  start_year  :integer          not null
#  status      :string           default("pending"), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
# Indexes
#
#  index_catalog_years_on_start_year  (start_year) UNIQUE
#
class CatalogYear < ApplicationRecord
  SOURCES = { html: "html", wayback: "wayback", pdf: "pdf" }.freeze
  STATUSES = { pending: "pending", imported: "imported", missing: "missing", failed: "failed" }.freeze

  enum :source, SOURCES, validate: true, prefix: true
  enum :status, STATUSES, validate: true

  has_many :requirement_sets, dependent: :destroy
  has_many :degree_programs, through: :requirement_sets
  has_many :catalog_year_courses, dependent: :delete_all

  validates :start_year, presence: true, uniqueness: true,
                         numericality: { only_integer: true, greater_than_or_equal_to: 2010 }

  # A catalog year starts in the fall: Fall 2026, Spring 2027, and Summer
  # 2027 are all in 2026-2027.
  def self.start_year_for(term)
    term.fall? ? term.year : term.year - 1
  end

  def self.for_term(term)
    find_by(start_year: start_year_for(term))
  end

  def name = "#{start_year}-#{start_year + 1}"
end

# frozen_string_literal: true

# Banner pages and search fields that the catalog did not store before:
# the catalog details, fees, learning objectives, and mutual exclusions of a
# course, and the part of term, campus, and cross-list group of a section.
class AddBannerCatalogDetails < ActiveRecord::Migration[8.1]
  def change
    add_column :catalog_courses, :college, :string
    add_column :catalog_courses, :division, :string
    add_column :catalog_courses, :department, :string
    add_column :catalog_courses, :levels, :string, array: true, default: [], null: false
    add_column :catalog_courses, :grading_modes, :string, array: true, default: [], null: false
    add_column :catalog_courses, :learning_objectives, :text
    add_column :catalog_courses, :mutual_exclusions, :jsonb, default: [], null: false
    add_column :catalog_courses, :fees, :jsonb, default: [], null: false

    add_column :courses, :part_of_term, :string
    add_column :courses, :campus, :string
    add_column :courses, :cross_list_identifier, :string
    add_column :courses, :cross_list_capacity, :integer
    add_column :courses, :cross_list_available, :integer
  end
end

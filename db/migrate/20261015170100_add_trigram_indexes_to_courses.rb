# frozen_string_literal: true

# Issue #684: the catalog `q` filter (Catalog::SectionQuery#apply_search)
# matches `ILIKE '%q%'` on the title, the subject, and the course number as
# text. A leading `%` cannot use a B-tree index, so each search read all of
# `courses` (40,780 rows, 83 ms in production on 2026-10-15). The three
# conditions are joined with OR, so the planner uses the indexes only when
# every condition has one.
#
# The indexes are built concurrently, so catalog imports can write to courses
# during the change.
class AddTrigramIndexesToCourses < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :courses, :title, name: "index_courses_on_title_trgm",
              using: :gin, opclass: :gin_trgm_ops, algorithm: :concurrently, if_not_exists: true
    add_index :courses, :subject, name: "index_courses_on_subject_trgm",
              using: :gin, opclass: :gin_trgm_ops, algorithm: :concurrently, if_not_exists: true
    # Matches `CAST(courses.course_number AS TEXT)` in the search condition.
    add_index :courses, "(course_number::text) gin_trgm_ops", name: "index_courses_on_course_number_text_trgm",
              using: :gin, algorithm: :concurrently, if_not_exists: true
  end
end

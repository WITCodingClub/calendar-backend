# frozen_string_literal: true

# Banner marks one instructor on a section as primary. We dropped that flag, so
# `course.faculties.first` returned whichever join row happened to be oldest.
# The join table also needs a primary key before it can back a has_many :through
# with dependent: :destroy.
class AddPrimaryIndicatorToCoursesFaculties < ActiveRecord::Migration[8.1]
  def change
    add_column :courses_faculties, :id, :primary_key
    add_column :courses_faculties, :primary_indicator, :boolean, default: false, null: false

    add_index :courses_faculties, [ :course_id, :primary_indicator ],
              name: "index_courses_faculties_on_course_id_and_primary"
  end
end

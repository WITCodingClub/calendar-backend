# frozen_string_literal: true

# An elective list can be a rule in place of a list of courses: any course
# in some subjects (an HSS elective: HIST, PSYC, ...) or any course at all (a
# free elective). DegreeRequirements::SharedElectives makes these lists.
class AddRulesToElectiveGroups < ActiveRecord::Migration[8.1]
  def change
    add_column :elective_groups, :subject_codes, :string, array: true, default: [], null: false
    add_column :elective_groups, :any_course, :boolean, default: false, null: false
  end
end

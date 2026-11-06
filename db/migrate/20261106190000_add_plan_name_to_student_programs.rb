# frozen_string_literal: true

# The plan of study a student picked for a program (#867), such as the "Three
# Year Program". Null means the plan is assumed: the standard plan of the
# program's catalog year.
class AddPlanNameToStudentPrograms < ActiveRecord::Migration[8.1]
  def change
    add_column :student_programs, :plan_name, :string
  end
end

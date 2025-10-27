class ChangeTermSemesterToSeason < ActiveRecord::Migration[8.1]
  def change
    safety_assured do
    rename_column :terms, :semester, :season
    end
  end
end

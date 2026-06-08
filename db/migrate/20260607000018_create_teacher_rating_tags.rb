class CreateTeacherRatingTags < ActiveRecord::Migration[8.1]
  def change
    create_table :teacher_rating_tags do |t|
      t.references :faculty, null: false, foreign_key: true
      t.integer :rmp_legacy_id, null: false
      t.string :tag_name, null: false
      t.integer :tag_count, default: 0
      t.timestamps
    end

    add_index :teacher_rating_tags, [ :faculty_id, :rmp_legacy_id ], unique: true
  end
end

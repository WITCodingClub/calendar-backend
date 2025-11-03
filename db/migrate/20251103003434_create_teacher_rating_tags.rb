class CreateTeacherRatingTags < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    create_table :teacher_rating_tags do |t|
      t.bigint :faculty_id, null: false
      t.integer :rmp_legacy_id, null: false
      t.string :tag_name, null: false
      t.integer :tag_count, default: 0

      t.timestamps
    end

    add_foreign_key :teacher_rating_tags, :faculties, validate: false
    add_index :teacher_rating_tags, [:faculty_id, :rmp_legacy_id], unique: true, algorithm: :concurrently
    add_index :teacher_rating_tags, :faculty_id, algorithm: :concurrently
  end
end

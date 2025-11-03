class CreateRmpRatings < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    create_table :rmp_ratings do |t|
      t.bigint :faculty_id, null: false
      t.string :rmp_id, null: false
      t.integer :clarity_rating
      t.integer :difficulty_rating
      t.integer :helpful_rating
      t.string :course_name
      t.text :comment
      t.datetime :rating_date
      t.string :grade
      t.boolean :would_take_again
      t.string :attendance_mandatory
      t.boolean :is_for_credit
      t.boolean :is_for_online_class
      t.text :rating_tags
      t.integer :thumbs_up_total, default: 0
      t.integer :thumbs_down_total, default: 0

      t.timestamps
    end

    # Add foreign key without validation
    add_foreign_key :rmp_ratings, :faculties, validate: false
    add_index :rmp_ratings, :rmp_id, unique: true, algorithm: :concurrently
    add_index :rmp_ratings, :faculty_id, algorithm: :concurrently
  end
end

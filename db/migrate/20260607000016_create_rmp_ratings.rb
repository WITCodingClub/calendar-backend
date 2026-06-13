class CreateRmpRatings < ActiveRecord::Migration[8.1]
  def change
    create_table :rmp_ratings do |t|
      t.references :faculty, null: false, foreign_key: true
      t.string :rmp_id, null: false
      t.text :comment
      t.string :course_name
      t.string :grade
      t.integer :clarity_rating
      t.integer :difficulty_rating
      t.integer :helpful_rating
      t.boolean :would_take_again
      t.boolean :is_for_credit
      t.boolean :is_for_online_class
      t.string :attendance_mandatory
      t.string :rating_tags
      t.integer :thumbs_up_total, default: 0
      t.integer :thumbs_down_total, default: 0
      t.datetime :rating_date
      t.timestamps
    end

    add_index :rmp_ratings, :rmp_id, unique: true
  end
end

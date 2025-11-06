class CreateEventPreferences < ActiveRecord::Migration[8.1]
  def change
    create_table :event_preferences do |t|
      t.references :user, null: false, foreign_key: true
      t.references :preferenceable, polymorphic: true, null: false
      t.text :title_template
      t.text :description_template
      t.jsonb :reminder_settings
      t.integer :color_id
      t.string :visibility

      t.timestamps
    end

    add_index :event_preferences, [:user_id, :preferenceable_type, :preferenceable_id],
              unique: true, name: 'index_event_prefs_on_user_and_preferenceable'
    add_index :event_preferences, [:preferenceable_type, :preferenceable_id],
              name: 'index_event_prefs_on_preferenceable'
  end
end

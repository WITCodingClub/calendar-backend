class CreatePreferenceTables < ActiveRecord::Migration[8.1]
  def change
    # Create calendar preferences table
    create_table :calendar_preferences do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :scope, null: false
      t.string :event_type
      t.text :title_template
      t.text :description_template
      t.jsonb :reminder_settings, default: []
      t.integer :color_id
      t.string :visibility

      t.timestamps
    end

    add_index :calendar_preferences, [:user_id, :scope, :event_type], unique: true, name: 'index_calendar_prefs_on_user_scope_type'

    # Create event preferences table
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

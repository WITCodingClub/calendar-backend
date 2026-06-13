class CreateUserExtensionConfigs < ActiveRecord::Migration[8.1]
  def change
    create_table :user_extension_configs do |t|
      t.references :user, null: false, foreign_key: true
      t.boolean :advanced_editing, default: false, null: false
      t.boolean :military_time, default: false, null: false
      t.boolean :sync_university_events, default: false, null: false
      t.string :default_color_lecture, default: "#039be5", null: false
      t.string :default_color_lab, default: "#f6bf26", null: false
      t.jsonb :university_event_categories
      t.timestamps
    end
  end
end

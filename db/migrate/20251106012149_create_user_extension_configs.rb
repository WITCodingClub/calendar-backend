class CreateUserExtensionConfigs < ActiveRecord::Migration[8.1]
  def change
    create_table :user_extension_configs do |t|
      t.references :user, null: false, foreign_key: true

      # interface UserSettings {
      #     military_time: boolean;
      #     default_color_lecture: string;
      #     default_color_lab: string;
      # }
      t.boolean :military_time, default: false, null: false
      t.string :default_color_lecture, null: false, default: GoogleColors::EVENT_PEACOCK
      t.string :default_color_lab, null: false, default: GoogleColors::EVENT_BANANA

      t.timestamps
    end
  end
end

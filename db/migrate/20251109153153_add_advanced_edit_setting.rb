class AddAdvancedEditSetting < ActiveRecord::Migration[8.1]
  def change
    # interface UserSettings {
    #     military_time: boolean;
    #     default_color_lecture: string;
    #     default_color_lab: string;
    #     advanced_editing: boolean;
    # }
    add_column :user_extension_configs, :advanced_editing, :boolean, default: false, null: false
  end
end

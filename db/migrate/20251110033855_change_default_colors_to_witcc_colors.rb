class ChangeDefaultColorsToWitccColors < ActiveRecord::Migration[8.1]
  def up
    # Change default values to WITCC colors
    change_column_default :user_extension_configs, :default_color_lecture, from: GoogleColors::EVENT_PEACOCK, to: GoogleColors::WITCC_PEACOCK
    change_column_default :user_extension_configs, :default_color_lab, from: GoogleColors::EVENT_BANANA, to: GoogleColors::WITCC_BANANA

    # Update existing records that have the old Google event color defaults to use WITCC colors
    UserExtensionConfig.where(default_color_lecture: GoogleColors::EVENT_PEACOCK).update_all(default_color_lecture: GoogleColors::WITCC_PEACOCK)
    UserExtensionConfig.where(default_color_lab: GoogleColors::EVENT_BANANA).update_all(default_color_lab: GoogleColors::WITCC_BANANA)
  end

  def down
    # Revert to Google event colors
    change_column_default :user_extension_configs, :default_color_lecture, from: GoogleColors::WITCC_PEACOCK, to: GoogleColors::EVENT_PEACOCK
    change_column_default :user_extension_configs, :default_color_lab, from: GoogleColors::WITCC_BANANA, to: GoogleColors::EVENT_BANANA

    # Update existing records back to Google event colors
    UserExtensionConfig.where(default_color_lecture: GoogleColors::WITCC_PEACOCK).update_all(default_color_lecture: GoogleColors::EVENT_PEACOCK)
    UserExtensionConfig.where(default_color_lab: GoogleColors::WITCC_BANANA).update_all(default_color_lab: GoogleColors::EVENT_BANANA)
  end
end

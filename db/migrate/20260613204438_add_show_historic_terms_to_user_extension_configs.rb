class AddShowHistoricTermsToUserExtensionConfigs < ActiveRecord::Migration[8.1]
  def change
    add_column :user_extension_configs, :show_historic_terms, :boolean, default: false, null: false
  end
end

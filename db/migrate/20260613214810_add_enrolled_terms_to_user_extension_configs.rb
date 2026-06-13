class AddEnrolledTermsToUserExtensionConfigs < ActiveRecord::Migration[8.1]
  def change
    add_column :user_extension_configs, :enrolled_terms, :jsonb, default: [], null: false
  end
end

class AddCatalogImportingToTerms < ActiveRecord::Migration[8.1]
  def change
    add_column :terms, :catalog_importing, :boolean, default: false, null: false
  end
end

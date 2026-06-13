class AddCatalogImportedToTerms < ActiveRecord::Migration[8.1]
  def change
    add_column :terms, :catalog_imported, :boolean, default: false, null: false
    add_column :terms, :catalog_imported_at, :datetime
  end
end

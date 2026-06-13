class AddCatalogImportFailureToTerms < ActiveRecord::Migration[8.1]
  def change
    add_column :terms, :catalog_import_failed, :boolean, default: false, null: false
    add_column :terms, :catalog_import_job_id, :string
  end
end

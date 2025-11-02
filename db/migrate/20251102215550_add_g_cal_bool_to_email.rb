class AddGCalBoolToEmail < ActiveRecord::Migration[8.1]
  def change
    add_column :emails, :g_cal, :boolean, default: false, null: false
  end
end

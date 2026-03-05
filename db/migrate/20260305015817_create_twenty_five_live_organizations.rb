# frozen_string_literal: true

class CreateTwentyFiveLiveOrganizations < ActiveRecord::Migration[8.1]
  def change
    create_table :twenty_five_live_organizations do |t|
      t.integer :organization_id,        null: false
      t.string  :organization_name
      t.string  :organization_title
      t.integer :organization_type_id
      t.string  :organization_type_name

      t.timestamps
    end

    add_index :twenty_five_live_organizations, :organization_id, unique: true
  end
end

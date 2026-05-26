# frozen_string_literal: true

class CreateOrganizations < ActiveRecord::Migration[8.1]
  def change
    create_table :twenty_five_live_organizations do |t|
      t.integer :twenty_five_live_id, null: false
      t.string  :code
      t.string  :name,                    null: false
      t.string  :organization_type_name

      t.timestamps
    end

    add_index :twenty_five_live_organizations, :twenty_five_live_id, unique: true

    add_check_constraint :twenty_five_live_organizations,
                         "length(trim(name)) > 0",
                         name: "twenty_five_live_organizations_name_not_blank"
  end
end

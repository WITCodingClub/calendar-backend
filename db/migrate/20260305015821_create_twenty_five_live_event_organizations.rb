# frozen_string_literal: true

class CreateTwentyFiveLiveEventOrganizations < ActiveRecord::Migration[8.1]
  def change
    create_table :twenty_five_live_event_organizations do |t|
      t.references :twenty_five_live_event,        null: false, foreign_key: true
      t.references :twenty_five_live_organization,  null: false, foreign_key: true
      t.boolean    :primary, default: false, null: false

      t.timestamps
    end

    add_index :twenty_five_live_event_organizations,
              %i[twenty_five_live_event_id twenty_five_live_organization_id],
              unique: true,
              name: "index_tfl_event_orgs_on_event_and_org"
  end
end

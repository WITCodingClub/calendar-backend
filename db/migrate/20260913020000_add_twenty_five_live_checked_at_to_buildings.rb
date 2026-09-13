# frozen_string_literal: true

class AddTwentyFiveLiveCheckedAtToBuildings < ActiveRecord::Migration[8.1]
  def change
    # When a 25Live sync last looked for this building. A building with no
    # formal name is only "not in 25Live" if a recent sync has looked.
    add_column :buildings, :twenty_five_live_checked_at, :datetime
  end
end

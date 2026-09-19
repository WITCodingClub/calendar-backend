# frozen_string_literal: true

# Where a provider puts the course events: in a calendar of their own
# ("separate"), or in the person's primary calendar ("primary"). Exchange works
# out free and busy time from the primary calendar only, so a person who wants
# classes to show as busy picks "primary".
class AddPlacementToCalendars < ActiveRecord::Migration[8.1]
  def change
    add_column :calendars, :placement, :string, default: "separate", null: false
  end
end

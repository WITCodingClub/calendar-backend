# frozen_string_literal: true

# Issue calendar-extension#120: Google Calendar now supports custom event
# colors, so a preference can hold any RGB color. Store the color as a
# lowercase "#rrggbb" hex string instead of a legacy Google colorId (1-11).
#
# Each legacy id becomes the hex of its palette color, as the Google Calendar
# web app shows it and as GoogleColors::COLOR_IDS lists it.
class StoreEventColorsAsHex < ActiveRecord::Migration[8.1]
  TABLES = %i[event_preferences calendar_preferences].freeze

  COLOR_IDS = {
    1  => "#7986cb",
    2  => "#33b679",
    3  => "#8e24aa",
    4  => "#e67c73",
    5  => "#f6bf26",
    6  => "#f4511e",
    7  => "#039be5",
    8  => "#616161",
    9  => "#3f51b5",
    10 => "#0b8043",
    11 => "#d50000"
  }.freeze

  DEFAULT_COLORS = { default_color_lecture: "#039be5", default_color_lab: "#f6bf26" }.freeze

  HEX_PATTERN = "^#[0-9a-f]{6}$"

  def up
    id_to_hex = COLOR_IDS.map { |id, hex| "WHEN #{id} THEN '#{hex}'" }.join(" ")

    TABLES.each do |table|
      change_column table, :color_id, :string, using: "CASE color_id #{id_to_hex} END"
    end

    # The extension could save any string here. Keep valid colors in lowercase
    # and put the column default back on anything else.
    DEFAULT_COLORS.each do |column, default|
      execute <<~SQL.squish
        UPDATE user_extension_configs
        SET #{column} = CASE WHEN lower(#{column}) ~ '#{HEX_PATTERN}' THEN lower(#{column}) ELSE '#{default}' END
        WHERE #{column} <> lower(#{column}) OR lower(#{column}) !~ '#{HEX_PATTERN}'
      SQL
    end
  end

  def down
    hex_to_id = COLOR_IDS.map { |id, hex| "WHEN '#{hex}' THEN #{id}" }.join(" ")

    # A custom color has no legacy id, so it becomes nil.
    TABLES.each do |table|
      change_column table, :color_id, :integer, using: "CASE color_id #{hex_to_id} END"
    end
  end
end

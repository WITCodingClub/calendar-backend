# frozen_string_literal: true

# Event colors are stored and sent as lowercase "#rrggbb" hex strings. Any RGB
# color is allowed, because Google Calendar supports custom event colors
# through event labels (see GoogleEventLabels).
module GoogleColors
  HEX_FORMAT = /\A#\h{6}\z/

  # The 11 colors of the Google Calendar event palette, as the Google Calendar
  # web app shows them.
  LAVENDER  = "#7986cb"
  SAGE      = "#33b679"
  GRAPE     = "#8e24aa"
  FLAMINGO  = "#e67c73"
  BANANA    = "#f6bf26"
  TANGERINE = "#f4511e"
  PEACOCK   = "#039be5"
  GRAPHITE  = "#616161"
  BLUEBERRY = "#3f51b5"
  BASIL     = "#0b8043"
  TOMATO    = "#d50000"

  # The legacy colorId of each palette color. Old extension versions send
  # these ids. A calendar without event labels accepts only these ids.
  COLOR_IDS = {
    1  => LAVENDER,
    2  => SAGE,
    3  => GRAPE,
    4  => FLAMINGO,
    5  => BANANA,
    6  => TANGERINE,
    7  => PEACOCK,
    8  => GRAPHITE,
    9  => BLUEBERRY,
    10 => BASIL,
    11 => TOMATO
  }.freeze

  # Returns the "#rrggbb" hex for a legacy color id (1-11, as an Integer or a
  # digit string) or for a hex color. Returns nil for any other value.
  def self.normalize(value)
    return COLOR_IDS[value] if value.is_a?(Integer)
    return nil unless value.is_a?(String)

    value = value.strip.downcase
    return COLOR_IDS[value.to_i] if value.match?(/\A\d+\z/)

    value if value.match?(HEX_FORMAT)
  end

  # For model attributes. Keeps a value that is not a color, so that the format
  # validation rejects it, and turns a blank value into nil.
  def self.normalize_attribute(value)
    return nil if value.blank?

    normalize(value) || value
  end

  # Returns the legacy color id whose palette color is nearest to the hex color.
  # Used for calendars that do not accept event labels.
  def self.nearest_color_id(hex)
    target = rgb(hex)

    COLOR_IDS.min_by do |_id, palette_hex|
      rgb(palette_hex).zip(target).sum { |a, b| (a - b)**2 }
    end.first
  end

  def self.rgb(hex)
    hex.delete_prefix("#").scan(/../).map { |pair| pair.to_i(16) }
  end
  private_class_method :rgb
end

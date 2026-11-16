# frozen_string_literal: true

module Preferences
  # Event colors are stored and sent as lowercase "#rrggbb" hex strings. Any RGB
  # color is allowed, because Google Calendar supports custom event colors
  # through event labels (see GoogleCalendar::EventLabels).
  #
  # PALETTE is the one table of the 11 colors of the Google Calendar event
  # palette. Each color has the legacy Google colorId that old extension
  # versions send and that a calendar without event labels accepts, and the
  # nearest Outlook category preset (MicrosoftGraph::CategoryCache).
  module Colors
    HEX_FORMAT = /\A#\h{6}\z/

    Color = Data.define(:name, :hex, :legacy_id, :outlook_preset)

    PALETTE = [
      Color.new(name: "lavender",  hex: "#7986cb", legacy_id: 1,  outlook_preset: "preset7"),
      Color.new(name: "sage",      hex: "#33b679", legacy_id: 2,  outlook_preset: "preset4"),
      Color.new(name: "grape",     hex: "#8e24aa", legacy_id: 3,  outlook_preset: "preset8"),
      Color.new(name: "flamingo",  hex: "#e67c73", legacy_id: 4,  outlook_preset: "preset9"),
      Color.new(name: "banana",    hex: "#f6bf26", legacy_id: 5,  outlook_preset: "preset3"),
      Color.new(name: "tangerine", hex: "#f4511e", legacy_id: 6,  outlook_preset: "preset1"),
      Color.new(name: "peacock",   hex: "#039be5", legacy_id: 7,  outlook_preset: "preset5"),
      Color.new(name: "graphite",  hex: "#616161", legacy_id: 8,  outlook_preset: "preset12"),
      Color.new(name: "blueberry", hex: "#3f51b5", legacy_id: 9,  outlook_preset: "preset22"),
      Color.new(name: "basil",     hex: "#0b8043", legacy_id: 10, outlook_preset: "preset19"),
      Color.new(name: "tomato",    hex: "#d50000", legacy_id: 11, outlook_preset: "preset0")
    ].freeze

    PALETTE.each { |color| const_set(color.name.upcase, color.hex) }

    COLOR_IDS = PALETTE.to_h { |color| [ color.legacy_id, color.hex ] }.freeze

    # The palette by the names the Google Calendar web app shows. The MCP tools
    # take these names.
    NAMES = PALETTE.to_h { |color| [ color.name, color.hex ] }.freeze

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

    # The palette color nearest to the hex color.
    def self.nearest(hex)
      target = rgb(hex)

      PALETTE.min_by { |color| rgb(color.hex).zip(target).sum { |a, b| (a - b)**2 } }
    end

    # Returns the legacy color id whose palette color is nearest to the hex color.
    # Used for calendars that do not accept event labels.
    def self.nearest_color_id(hex)
      nearest(hex).legacy_id
    end

    def self.rgb(hex)
      hex.delete_prefix("#").scan(/../).map { |pair| pair.to_i(16) }
    end
    private_class_method :rgb
  end
end

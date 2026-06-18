# frozen_string_literal: true

module GoogleColors
  EVENT_LAVENDER  = "#a4bdfc"
  EVENT_SAGE      = "#7ae7bf"
  EVENT_GRAPE     = "#dbadff"
  EVENT_FLAMINGO  = "#ff887c"
  EVENT_BANANA    = "#fbd75b"
  EVENT_TANGERINE = "#ffb878"
  EVENT_PEACOCK   = "#46d6db"
  EVENT_GRAPHITE  = "#e1e1e1"
  EVENT_BLUEBERRY = "#5484ed"
  EVENT_BASIL     = "#51b749"
  EVENT_TOMATO    = "#dc2127"

  WITCC_TOMATO    = "#d50000"
  WITCC_FLAMINGO  = "#e67c73"
  WITCC_TANGERINE = "#f4511e"
  WITCC_BANANA    = "#f6bf26"
  WITCC_SAGE      = "#33b679"
  WITCC_BASIL     = "#0b8043"
  WITCC_PEACOCK   = "#039be5"
  WITCC_BLUEBERRY = "#3f51b5"
  WITCC_LAVENDER  = "#7986cb"
  WITCC_GRAPE     = "#8e24aa"
  WITCC_GRAPHITE  = "#616161"

  EVENT_MAP = {
    1  => EVENT_LAVENDER,
    2  => EVENT_SAGE,
    3  => EVENT_GRAPE,
    4  => EVENT_FLAMINGO,
    5  => EVENT_BANANA,
    6  => EVENT_TANGERINE,
    7  => EVENT_PEACOCK,
    8  => EVENT_GRAPHITE,
    9  => EVENT_BLUEBERRY,
    10 => EVENT_BASIL,
    11 => EVENT_TOMATO,
    lavender:  EVENT_LAVENDER,
    sage:      EVENT_SAGE,
    grape:     EVENT_GRAPE,
    flamingo:  EVENT_FLAMINGO,
    banana:    EVENT_BANANA,
    tangerine: EVENT_TANGERINE,
    peacock:   EVENT_PEACOCK,
    graphite:  EVENT_GRAPHITE,
    blueberry: EVENT_BLUEBERRY,
    basil:     EVENT_BASIL,
    tomato:    EVENT_TOMATO,
    blue:   EVENT_BLUEBERRY,
    green:  EVENT_BASIL,
    red:    EVENT_TOMATO,
    yellow: EVENT_BANANA,
    orange: EVENT_TANGERINE,
    purple: EVENT_GRAPE,
    gray:   EVENT_GRAPHITE
  }.freeze

  WITCC_MAP = {
    WITCC_TOMATO    => EVENT_TOMATO,
    WITCC_FLAMINGO  => EVENT_FLAMINGO,
    WITCC_TANGERINE => EVENT_TANGERINE,
    WITCC_BANANA    => EVENT_BANANA,
    WITCC_SAGE      => EVENT_SAGE,
    WITCC_BASIL     => EVENT_BASIL,
    WITCC_PEACOCK   => EVENT_PEACOCK,
    WITCC_BLUEBERRY => EVENT_BLUEBERRY,
    WITCC_LAVENDER  => EVENT_LAVENDER,
    WITCC_GRAPE     => EVENT_GRAPE,
    WITCC_GRAPHITE  => EVENT_GRAPHITE
  }.freeze

  def self.witcc_to_color_id(witcc_hex)
    return nil if witcc_hex.blank?

    google_event_hex = WITCC_MAP[witcc_hex.downcase]
    return nil unless google_event_hex

    EVENT_MAP.each { |k, v| return k if k.is_a?(Integer) && v == google_event_hex }
    nil
  end

  def self.to_witcc_hex(color_id_or_hex)
    return nil if color_id_or_hex.blank?

    google_event_hex = if color_id_or_hex.is_a?(Integer)
                         EVENT_MAP[color_id_or_hex]
    elsif color_id_or_hex.is_a?(String) && color_id_or_hex.start_with?("#")
                         color_id_or_hex.downcase
    end

    return nil unless google_event_hex

    WITCC_MAP.each { |witcc, event| return witcc if event == google_event_hex }
    nil
  end
end

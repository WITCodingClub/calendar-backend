# frozen_string_literal: true

module GoogleColors
  # Event Colors
  EVENT_LAVENDER = "#a4bdfc"
  EVENT_SAGE = "#7ae7bf"
  EVENT_GRAPE = "#dbadff"
  EVENT_FLAMINGO = "#ff887c"
  EVENT_BANANA = "#fbd75b"
  EVENT_TANGERINE = "#ffb878"
  EVENT_PEACOCK = "#46d6db"
  EVENT_GRAPHITE = "#e1e1e1"
  EVENT_BLUEBERRY = "#5484ed"
  EVENT_BASIL = "#51b749"
  EVENT_TOMATO = "#dc2127"

  # Calendar Colors (first 12 for brevity, extend as needed)
  CAL_COCOA = "#ac725e"
  CAL_BIRCH = "#d06b64"
  CAL_CHERRY = "#f83a22"
  CAL_FIRE = "#fa573c"
  CAL_MANDARIN = "#ff7537"
  CAL_PUMPKIN = "#ffad46"
  CAL_AVOCADO = "#42d692"
  CAL_EUCALYPTUS = "#16a765"
  CAL_PISTACHIO = "#7bd148"
  CAL_CITRON = "#b3dc6c"
  CAL_LEMON = "#fbe983"
  CAL_MANGO = "#fad165"
  CAL_SEAFOAM = "#92e1c0"
  CAL_POOL = "#9fe1e7"
  CAL_SKY = "#9fc6e7"
  CAL_COBALT = "#4986e7"
  CAL_AMETHYST = "#9a9cff"
  CAL_WISTERIA = "#b99aff"
  CAL_SILVER = "#c2c2c2"
  CAL_MUSHROOM = "#cabdbf"
  CAL_ROSE = "#cca6ac"
  CAL_BUBBLEGUM = "#f691b2"
  CAL_LAVENDER = "#cd74e6"
  CAL_PURPLE = "#a47ae2"

  # Standard foreground color for all
  FOREGROUND = "#1d1d1d"

  # WITCC Colors
  WITCC_TOMATO = "#d50000"
  WITCC_FLAMINGO = "#e67c73"
  WITCC_TANGERINE = "#f4511e"
  WITCC_BANANA = "#f6bf26"
  WITCC_SAGE = "#33b679"
  WITCC_BASIL = "#0b8043"
  WITCC_PEACOCK = "#039be5"
  WITCC_BLUEBERRY = "#3f51b5"
  WITCC_LAVENDER = "#7986cb"
  WITCC_GRAPE = "#8e24aa"
  WITCC_GRAPHITE = "#616161"

  # Event colors map
  EVENT_MAP = {
    1 => EVENT_LAVENDER,
    2 => EVENT_SAGE,
    3 => EVENT_GRAPE,
    4 => EVENT_FLAMINGO,
    5 => EVENT_BANANA,
    6 => EVENT_TANGERINE,
    7 => EVENT_PEACOCK,
    8 => EVENT_GRAPHITE,
    9 => EVENT_BLUEBERRY,
    10 => EVENT_BASIL,
    11 => EVENT_TOMATO,
    # Named access
    lavender: EVENT_LAVENDER,
    sage: EVENT_SAGE,
    grape: EVENT_GRAPE,
    flamingo: EVENT_FLAMINGO,
    banana: EVENT_BANANA,
    tangerine: EVENT_TANGERINE,
    peacock: EVENT_PEACOCK,
    graphite: EVENT_GRAPHITE,
    blueberry: EVENT_BLUEBERRY,
    basil: EVENT_BASIL,
    tomato: EVENT_TOMATO,
    # Common aliases
    blue: EVENT_BLUEBERRY,
    green: EVENT_BASIL,
    red: EVENT_TOMATO,
    yellow: EVENT_BANANA,
    orange: EVENT_TANGERINE,
    purple: EVENT_GRAPE,
    gray: EVENT_GRAPHITE
  }.freeze

  # Calendar colors map
  CALENDAR_MAP = {
    1 => CAL_COCOA,
    2 => CAL_BIRCH,
    3 => CAL_CHERRY,
    4 => CAL_FIRE,
    5 => CAL_MANDARIN,
    6 => CAL_PUMPKIN,
    7 => CAL_AVOCADO,
    8 => CAL_EUCALYPTUS,
    9 => CAL_PISTACHIO,
    10 => CAL_CITRON,
    11 => CAL_LEMON,
    12 => CAL_MANGO,
    13 => CAL_SEAFOAM,
    14 => CAL_POOL,
    15 => CAL_SKY,
    16 => CAL_COBALT,
    17 => CAL_AMETHYST,
    18 => CAL_WISTERIA,
    19 => CAL_SILVER,
    20 => CAL_MUSHROOM,
    21 => CAL_ROSE,
    22 => CAL_BUBBLEGUM,
    23 => CAL_LAVENDER,
    24 => CAL_PURPLE,
    # Named access
    cocoa: CAL_COCOA,
    brown: CAL_COCOA,
    pink: CAL_BUBBLEGUM,
    cobalt: CAL_COBALT,
    silver: CAL_SILVER,
    purple: CAL_PURPLE
  }.freeze


  # I need a way to map the witcc colors to the event colors
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

  # Convert a WITCC color hex to Google Calendar event color ID (1-11)
  # @param witcc_hex [String] WITCC color hex value (e.g., "#d50000")
  # @return [Integer, nil] Google Calendar color ID (1-11), or nil if not found
  def self.witcc_to_color_id(witcc_hex)
    return nil if witcc_hex.blank?

    # Normalize hex input (case-insensitive)
    normalized_hex = witcc_hex.downcase

    # Map WITCC color to Google event color
    google_event_hex = WITCC_MAP[normalized_hex]
    return nil unless google_event_hex

    # Find the color ID in EVENT_MAP by searching for the hex value
    EVENT_MAP.each do |key, hex|
      return key if key.is_a?(Integer) && hex == google_event_hex
    end

    nil
  end
end

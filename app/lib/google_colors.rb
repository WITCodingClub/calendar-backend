module GoogleColors
  # Event Colors
  EVENT_LAVENDER = "#a4bdfc".freeze
  EVENT_SAGE = "#7ae7bf".freeze
  EVENT_GRAPE = "#dbadff".freeze
  EVENT_FLAMINGO = "#ff887c".freeze
  EVENT_BANANA = "#fbd75b".freeze
  EVENT_TANGERINE = "#ffb878".freeze
  EVENT_PEACOCK = "#46d6db".freeze
  EVENT_GRAPHITE = "#e1e1e1".freeze
  EVENT_BLUEBERRY = "#5484ed".freeze
  EVENT_BASIL = "#51b749".freeze
  EVENT_TOMATO = "#dc2127".freeze

  # Calendar Colors (first 12 for brevity, extend as needed)
  CAL_COCOA = "#ac725e".freeze
  CAL_BIRCH = "#d06b64".freeze
  CAL_CHERRY = "#f83a22".freeze
  CAL_FIRE = "#fa573c".freeze
  CAL_MANDARIN = "#ff7537".freeze
  CAL_PUMPKIN = "#ffad46".freeze
  CAL_AVOCADO = "#42d692".freeze
  CAL_EUCALYPTUS = "#16a765".freeze
  CAL_PISTACHIO = "#7bd148".freeze
  CAL_CITRON = "#b3dc6c".freeze
  CAL_LEMON = "#fbe983".freeze
  CAL_MANGO = "#fad165".freeze
  CAL_SEAFOAM = "#92e1c0".freeze
  CAL_POOL = "#9fe1e7".freeze
  CAL_SKY = "#9fc6e7".freeze
  CAL_COBALT = "#4986e7".freeze
  CAL_AMETHYST = "#9a9cff".freeze
  CAL_WISTERIA = "#b99aff".freeze
  CAL_SILVER = "#c2c2c2".freeze
  CAL_MUSHROOM = "#cabdbf".freeze
  CAL_ROSE = "#cca6ac".freeze
  CAL_BUBBLEGUM = "#f691b2".freeze
  CAL_LAVENDER = "#cd74e6".freeze
  CAL_PURPLE = "#a47ae2".freeze

  # Standard foreground color for all
  FOREGROUND = "#1d1d1d".freeze

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
end
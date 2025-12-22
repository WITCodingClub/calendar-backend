# frozen_string_literal: true

module FlipperFlags
  V1 = :"2025_10_04_v1"
  V2 = :"2025_11_12_v2"
  # rubocop:disable Lint/SymbolConversion, Style/SymbolLiteral
  ENV_SWITCHER = :"env_switcher"
  DEBUG_MODE = :"debug_mode"
  FINALS_RETROACTIVE = :"finals_retroactive"
  # rubocop:enable Lint/SymbolConversion, Style/SymbolLiteral

  MAP = {
    v1: V1,
    v2: V2,
    envSwitcher: ENV_SWITCHER,
    debugMode: DEBUG_MODE,
    finalsRetroactive: FINALS_RETROACTIVE,
  }.freeze

  ALL_FLAGS = [
    :v1,
    :v2,
    :envSwitcher,
    :debugMode,
    :finalsRetroactive,
  ].freeze


end

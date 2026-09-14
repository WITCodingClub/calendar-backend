# frozen_string_literal: true

module FlipperFlags
  ENV_SWITCHER = :env_switcher
  DEBUG_MODE = :debug_mode
  FINALS_RETROACTIVE = :finals_retroactive
  BYPASS_RATE_LIMITS = :bypass_rate_limits
  MICROSOFT_SIGN_IN = :microsoft_sign_in
  MICROSOFT_GRAPH_CALENDAR = :microsoft_graph_calendar

  MAP = {
    envSwitcher: ENV_SWITCHER,
    debugMode: DEBUG_MODE,
    finalsRetroactive: FINALS_RETROACTIVE,
    bypassRateLimits: BYPASS_RATE_LIMITS,
    microsoftSignIn: MICROSOFT_SIGN_IN,
    microsoftGraphCalendar: MICROSOFT_GRAPH_CALENDAR
  }.freeze

  ALL_FLAGS = %i[
    envSwitcher
    debugMode
    finalsRetroactive
    bypassRateLimits
    microsoftSignIn
    microsoftGraphCalendar
  ].freeze
end

# frozen_string_literal: true

module FlipperFlags
  ENV_SWITCHER = :env_switcher
  DEBUG_MODE = :debug_mode
  FINALS_RETROACTIVE = :finals_retroactive
  BYPASS_RATE_LIMITS = :bypass_rate_limits
  MICROSOFT_SIGN_IN = :microsoft_sign_in
  MICROSOFT_GRAPH_CALENDAR = :microsoft_graph_calendar
  FRIEND_MEETING_EVENTS = :friend_meeting_events
  FRIENDS_AVAILABILITY_ONLY = :friends_availability_only
  MEETING_LINKS = :meeting_links

  MAP = {
    envSwitcher: ENV_SWITCHER,
    debugMode: DEBUG_MODE,
    finalsRetroactive: FINALS_RETROACTIVE,
    bypassRateLimits: BYPASS_RATE_LIMITS,
    microsoftSignIn: MICROSOFT_SIGN_IN,
    microsoftGraphCalendar: MICROSOFT_GRAPH_CALENDAR,
    friendMeetingEvents: FRIEND_MEETING_EVENTS,
    friendsAvailabilityOnly: FRIENDS_AVAILABILITY_ONLY,
    meetingLinks: MEETING_LINKS
  }.freeze

  ALL_FLAGS = %i[
    envSwitcher
    debugMode
    finalsRetroactive
    bypassRateLimits
    microsoftSignIn
    microsoftGraphCalendar
    friendMeetingEvents
    friendsAvailabilityOnly
    meetingLinks
  ].freeze
end

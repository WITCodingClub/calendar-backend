# frozen_string_literal: true

module FeatureFlags
  ENV_SWITCHER = :env_switcher
  DEBUG_MODE = :debug_mode
  FINALS_RETROACTIVE = :finals_retroactive
  BYPASS_RATE_LIMITS = :bypass_rate_limits
  MICROSOFT_SIGN_IN = :microsoft_sign_in
  MICROSOFT_GRAPH_CALENDAR = :microsoft_graph_calendar
  FRIENDS_AVAILABILITY_ONLY = :friends_availability_only
  SEMANTIC_SEARCH = :semantic_search
  FRIEND_MEETING_EVENTS = :friend_meeting_events
  FRIEND_GROUPS = :friend_groups
  FRIEND_EXPIRY = :friend_expiry
  MEETING_LINKS = :meeting_links
  DEGREE_PLANNING = :degree_planning
  SCHEDULE_BUILDER = :schedule_builder

  MAP = {
    envSwitcher: ENV_SWITCHER,
    debugMode: DEBUG_MODE,
    finalsRetroactive: FINALS_RETROACTIVE,
    bypassRateLimits: BYPASS_RATE_LIMITS,
    microsoftSignIn: MICROSOFT_SIGN_IN,
    microsoftGraphCalendar: MICROSOFT_GRAPH_CALENDAR,
    friendsAvailabilityOnly: FRIENDS_AVAILABILITY_ONLY,
    friendMeetingEvents: FRIEND_MEETING_EVENTS,
    friendGroups: FRIEND_GROUPS,
    friendExpiry: FRIEND_EXPIRY,
    meetingLinks: MEETING_LINKS,
    degreePlanning: DEGREE_PLANNING,
    scheduleBuilder: SCHEDULE_BUILDER
  }.freeze

  ALL_FLAGS = %i[
    envSwitcher
    debugMode
    finalsRetroactive
    bypassRateLimits
    microsoftSignIn
    microsoftGraphCalendar
    friendsAvailabilityOnly
    friendMeetingEvents
    friendGroups
    friendExpiry
    meetingLinks
    degreePlanning
    scheduleBuilder
  ].freeze

  # How long one process keeps flag reads (config/initializers/flipper.rb).
  CACHE_TTL = 1.minute

  # The cache in front of the Flipper tables. Rails.cache is Solid Cache in
  # production, so a read there is a database query on every request (#682).
  # Outside specs, flags stay in this process instead. Specs keep Rails.cache
  # (a null store), so no flag state carries over between examples.
  def self.build_cache(env: Rails.env)
    env.test? ? Rails.cache : ActiveSupport::Cache::MemoryStore.new(size: 1.megabyte)
  end
end

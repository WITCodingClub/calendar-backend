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

  # Every flag, with its description in the Flipper UI. Add a flag here
  # before you call Flipper.enabled? on it: config/initializers/flipper.rb
  # creates each one, so it shows in the Flipper UI before anyone turns it on.
  DESCRIPTIONS = {
    ENV_SWITCHER => "Allows switching between dev/staging/production environments",
    DEBUG_MODE => "Enables verbose debug logging and diagnostic output",
    FINALS_RETROACTIVE => "Enables retroactive finals schedule processing for past terms",
    BYPASS_RATE_LIMITS => "Bypasses rate limiting for trusted users and admins",
    MICROSOFT_SIGN_IN => "Sign in with Microsoft. Global only: enable it fully, not per actor",
    MICROSOFT_GRAPH_CALENDAR => "Microsoft Graph calendar sync. Needs Entra admin consent first",
    FRIENDS_AVAILABILITY_ONLY => "Friends can share only busy blocks. Needs the privacy policy update (calendar-website#20)",
    SEMANTIC_SEARCH => "Catalog search by meaning. Global only: it needs OPENAI_API_KEY too",
    FRIEND_MEETING_EVENTS => "Friends v6: make a calendar event from a suggested meeting time. Waits on the privacy policy update",
    FRIEND_GROUPS => "Friend groups in the API and dashboard. Off until the privacy policy update",
    FRIEND_EXPIRY => "Set, extend, or remove an expiry date on a friendship. Needs the privacy policy update first",
    MEETING_LINKS => "One-time meeting links for people who are not friends. Checked for the link owner. Waits on the privacy policy update",
    DEGREE_PLANNING => "My programs page and the programs and degree progress API. Checked per user. MCP tools stay on: their scopes are the gate",
    SCHEDULE_BUILDER => "The schedule builder: POST /api/v1/catalog/schedule_options and the find_schedules MCP tool. Global, or per user with a token"
  }.freeze

  # Flags that GET /api/user/feature_flags does not send to the extension.
  SERVER_ONLY = [ SEMANTIC_SEARCH ].freeze

  # The camelCase name that the extension reads, for each flag it gets.
  MAP = (DESCRIPTIONS.keys - SERVER_ONLY).index_by { |flag| flag.to_s.camelize(:lower).to_sym }.freeze
  ALL_FLAGS = MAP.keys.freeze

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

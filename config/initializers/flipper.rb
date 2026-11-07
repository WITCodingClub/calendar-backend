# frozen_string_literal: true

require Rails.root.join("app/lib/feature_flags")
require Rails.root.join("app/lib/feature_flags/user_actor_adapter")
require Rails.root.join("app/lib/feature_flags/groups")

# Canonical list of every Flipper flag used in the app. Add a flag here before
# calling Flipper.enabled? anywhere — this ensures it appears in the Flipper UI
# even before it's been toggled, making it easy to discover and enable without
# manually creating it in the dashboard.
#
# Keys are the actual Flipper flag identifiers (matching FeatureFlags constants).
# Flags are created disabled by default; Flipper.add is idempotent and never
# resets an already-enabled flag.
FLIPPER_FLAGS = {
  FeatureFlags::ENV_SWITCHER     => "Allows switching between dev/staging/production environments",
  FeatureFlags::DEBUG_MODE       => "Enables verbose debug logging and diagnostic output",
  FeatureFlags::FINALS_RETROACTIVE => "Enables retroactive finals schedule processing for past terms",
  FeatureFlags::BYPASS_RATE_LIMITS => "Bypasses rate limiting for trusted users and admins",
  FeatureFlags::MICROSOFT_SIGN_IN => "Sign in with Microsoft. Global only: enable it fully, not per actor",
  FeatureFlags::MICROSOFT_GRAPH_CALENDAR => "Microsoft Graph calendar sync. Needs Entra admin consent first",
  FeatureFlags::FRIENDS_AVAILABILITY_ONLY => "Friends can share only busy blocks. Needs the privacy policy update (calendar-website#20)",
  FeatureFlags::SEMANTIC_SEARCH => "Catalog search by meaning. Global only: it needs OPENAI_API_KEY too",
  FeatureFlags::FRIEND_MEETING_EVENTS => "Friends v6: make a calendar event from a suggested meeting time. Waits on the privacy policy update",
  FeatureFlags::FRIEND_GROUPS => "Friend groups in the API and dashboard. Off until the privacy policy update",
  FeatureFlags::FRIEND_EXPIRY => "Set, extend, or remove an expiry date on a friendship. Needs the privacy policy update first",
  FeatureFlags::MEETING_LINKS => "One-time meeting links for people who are not friends. Checked for the link owner. Waits on the privacy policy update",
  FeatureFlags::DEGREE_PLANNING => "My programs page and the programs and degree progress API. Checked per user. MCP tools stay on: their scopes are the gate"
}.freeze

# The Flipper engine adds its memoizer after Rack::Attack, so the
# privileged-users safelist read its flag outside the memoized request. Turn
# the engine's memoizer off and put one in front of Rack::Attack instead. It
# preloads every flag once for each request (#682).
Rails.application.configure do
  config.flipper.memoize = false
  config.middleware.insert_before Rack::Attack, Flipper::Middleware::Memoizer, preload: true
end

# Flag reads stay in this process for FeatureFlags::CACHE_TTL (#682). A flag
# change, from the Flipper UI or from another process such as `rails runner`
# or the other deploy slot, shows in every process within that time. The
# Flipper UI usually clears this process's copy at once, but a request that
# read the flags just before the change can write the old value back. Before
# you add Puma workers or a separate jobs container, remember that each process
# has its own copy.
Flipper.configure do |config|
  config.use FeatureFlags::UserActorAdapter
  config.use Flipper::Adapters::ActiveSupportCacheStore, FeatureFlags.build_cache, FeatureFlags::CACHE_TTL
end

Flipper::UI.configure do |config|
  config.actor_names_source = ->(actor_ids) { FeatureFlags::ActorNames.call(actor_ids) }
  # The version check fetches www.flippercloud.io from the browser, which the
  # Content Security Policy does not allow. Dependabot reports new versions.
  config.version_check_enabled = false
end

# Group gates. FeatureFlags::Groups unwraps the actor that Flipper passes a group
# block, so a group matches the user behind it.
FeatureFlags::Groups.register_all

# Ensure every flag in FLIPPER_FLAGS exists in the store so the Flipper UI
# always shows the full list, even in fresh environments.
#
# Guard on the table existing: this hook fires on every boot, including the
# environment load at the start of `rails db:migrate` (db:migrate =>
# db:load_config => environment). On a fresh, not-yet-migrated DB (preview
# envs, CI, first-time setup) flipper_features doesn't exist yet, and an
# unconditional Flipper.add would crash the migrate with PG::UndefinedTable.
# Flags register on the next boot, once the table exists.
Rails.application.config.after_initialize do
  if ActiveRecord::Base.connection.data_source_exists?("flipper_features")
    FLIPPER_FLAGS.each_key { |flag| Flipper.add(flag) }
  end
rescue ActiveRecord::ConnectionNotEstablished,
       ActiveRecord::NoDatabaseError,
       ActiveRecord::StatementInvalid
  # DB not reachable / not yet created / pre-migrate — skip registration.
  # Flags re-register on the next boot once the schema is loaded.
end

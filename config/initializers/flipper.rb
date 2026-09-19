# frozen_string_literal: true

require Rails.root.join("app/lib/flipper_flags")
require Rails.root.join("app/lib/flipper_user_actor_adapter")
require Rails.root.join("app/lib/flipper_groups")

# Canonical list of every Flipper flag used in the app. Add a flag here before
# calling Flipper.enabled? anywhere — this ensures it appears in the Flipper UI
# even before it's been toggled, making it easy to discover and enable without
# manually creating it in the dashboard.
#
# Keys are the actual Flipper flag identifiers (matching FlipperFlags constants).
# Flags are created disabled by default; Flipper.add is idempotent and never
# resets an already-enabled flag.
FLIPPER_FLAGS = {
  FlipperFlags::ENV_SWITCHER     => "Allows switching between dev/staging/production environments",
  FlipperFlags::DEBUG_MODE       => "Enables verbose debug logging and diagnostic output",
  FlipperFlags::FINALS_RETROACTIVE => "Enables retroactive finals schedule processing for past terms",
  FlipperFlags::BYPASS_RATE_LIMITS => "Bypasses rate limiting for trusted users and admins",
  FlipperFlags::MICROSOFT_SIGN_IN => "Sign in with Microsoft. Global only: enable it fully, not per actor",
  FlipperFlags::MICROSOFT_GRAPH_CALENDAR => "Microsoft Graph calendar sync. Needs Entra admin consent first"
}.freeze

Rails.application.configure do
  config.flipper.memoize = true
end

Flipper.configure do |config|
  config.use FlipperUserActorAdapter
  config.use Flipper::Adapters::ActiveSupportCacheStore, Rails.cache, 5.minutes
end

Flipper::UI.configure do |config|
  config.actor_names_source = ->(actor_ids) { FlipperActorNames.call(actor_ids) }
end

# Group gates. FlipperGroups unwraps the actor that Flipper passes a group
# block, so a group matches the user behind it.
FlipperGroups.register_all

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

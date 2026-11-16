# frozen_string_literal: true

require Rails.root.join("app/lib/feature_flags")
require Rails.root.join("app/lib/feature_flags/user_actor_adapter")
require Rails.root.join("app/lib/feature_flags/groups")

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

# Create every flag in FeatureFlags::DESCRIPTIONS, so the Flipper UI always
# shows the full list, even in fresh environments.
#
# Guard on the table existing: this hook fires on every boot, including the
# environment load at the start of `rails db:migrate` (db:migrate =>
# db:load_config => environment). On a fresh, not-yet-migrated DB (preview
# envs, CI, first-time setup) flipper_features doesn't exist yet, and an
# unconditional Flipper.add would crash the migrate with PG::UndefinedTable.
# Flags register on the next boot, once the table exists.
Rails.application.config.after_initialize do
  if ActiveRecord::Base.connection.data_source_exists?("flipper_features")
    FeatureFlags::DESCRIPTIONS.each_key { |flag| Flipper.add(flag) }
  end
rescue ActiveRecord::ConnectionNotEstablished,
       ActiveRecord::NoDatabaseError,
       ActiveRecord::StatementInvalid
  # DB not reachable / not yet created / pre-migrate — skip registration.
  # Flags re-register on the next boot once the schema is loaded.
end

# frozen_string_literal: true

require Rails.root.join("app/lib/flipper_flags")

Rails.application.configure do
  ## Memoization ensures that only one adapter call is made per feature per request.
  ## For more info, see https://www.flippercloud.io/docs/optimization#memoization
  config.flipper.memoize = true

  ## Flipper preloads all features before each request, which is recommended if:
  ##   * you have a limited number of features (< 100?)
  ##   * most of your requests depend on most of your features
  ##   * you have limited gate data combined across all features (< 1k enabled gates, like individual actors, across all features)
  ##
  ## For more info, see https://www.flippercloud.io/docs/optimization#preloading
  # config.flipper.preload = true

  ## Warn or raise an error if an unknown feature is checked
  ## Can be set to `:warn`, `:raise`, or `false`
  # config.flipper.strict = Rails.env.development? && :warn

  ## Show Flipper checks in logs
  # config.flipper.log = true

  ## Reconfigure Flipper to use the Memory adapter and disable Cloud in tests
  # config.flipper.test_help = true

  ## The path that Flipper Cloud will use to sync features
  # config.flipper.cloud_path = "_flipper"

  ## The instrumenter that Flipper will use. Defaults to ActiveSupport::Notifications.
  # config.flipper.instrumenter = ActiveSupport::Notifications
end

Flipper.configure do |config|
  ## Configure other adapters that you want to use here:
  ## See http://flippercloud.io/docs/adapters
  # config.use Flipper::Adapters::ActiveSupportCacheStore, Rails.cache, expires_in: 5.minutes
end

## Register a group that can be used for enabling features.
##
##   Flipper.enable_group :my_feature, :admins
##
## See https://www.flippercloud.io/docs/features#enablement-group
#
# Flipper.register(:admins) do |actor|
#  actor.respond_to?(:admin?) && actor.admin?
# end

Flipper::UI.configure do |config|
  config.actor_names_source = ->(actor_ids) {
    # Lookup actor_ids and return hash with user ID => primary email
    User.where(id: actor_ids)
        .joins(:emails)
        .where(emails: { primary: true })
        .pluck(:id, "emails.email")
        .to_h
  }
end


Flipper.register(:users) do |actor, _context|
  actor.is_a?(User)
end

Flipper.register(:admins) do |actor, _context|
  actor.is_a?(User) && actor.admin_access?
end

Flipper.register(:super_admins) do |actor, _context|
  actor.is_a?(User) && (actor.super_admin? || actor.owner?)
end

Flipper.register(:owners) do |actor, _context|
  actor.is_a?(User) && actor.owner?
end

# Auto-create all declared feature flags if they don't exist
# Run this manually with: rails flipper:ensure_flags
# TODO: Auto-creation disabled due to initialization order issues

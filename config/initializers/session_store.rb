# frozen_string_literal: true

# Use cookie store in test/development environments to avoid Redis dependency
# Use Redis session store in production/staging for persistence
if Rails.env.production? || Rails.env.staging?
  Rails.application.config.session_store :redis_session_store,
                                         servers: ENV.fetch("REDIS_URL", "redis://localhost:6379/2/session"),
                                         expire_after: 30.days,
                                         key: "_#{Rails.application.class.module_parent_name.underscore}_session",
                                         threadsafe: true,
                                         signed: true,
                                         httponly: true,
                                         secure: Rails.env.production?
else
  Rails.application.config.session_store :cookie_store,
                                         key: "_#{Rails.application.class.module_parent_name.underscore}_session"
end

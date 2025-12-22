# frozen_string_literal: true

Rails.application.config.session_store :redis_session_store,
                                       servers: ENV.fetch("REDIS_URL", "redis://localhost:6379/2/session"),
                                       expire_after: 30.days,
                                       key: "_#{Rails.application.class.module_parent_name.underscore}_session",
                                       threadsafe: true,
                                       signed: true,
                                       httponly: true,
                                       secure: Rails.env.production?

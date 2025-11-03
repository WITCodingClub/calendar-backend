Rails.application.config.session_store :redis_session_store,
                                       servers: ENV.fetch("REDIS_URL") { "redis://localhost:6379/2/session" },
                                       expire_after: Rails.env.in?(%w[development development_wcreds]) ? 30.days : 90.minutes,
                                       key: "_#{Rails.application.class.module_parent_name.underscore}_session",
                                       threadsafe: true,
                                       signed: true,
                                       httponly: true,
                                       secure: Rails.env.production?

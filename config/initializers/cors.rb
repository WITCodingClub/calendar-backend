# frozen_string_literal: true

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins_list = [
      "http://localhost:3001",
      "https://localhost:3001",
      /\Ahttps?:\/\/localhost:\d+\z/
    ]
    origins_list << /\Achrome-extension:\/\/.+\z/ if Rails.env.development?

    origins(*origins_list)

    resource "/api/*",
             headers: :any,
             methods: [ :get, :post, :put, :patch, :delete, :options, :head ],
             credentials: true,
             expose: [ "Authorization" ]
  end

  # The public catalog API carries no credentials and no user data, so any
  # origin may read it. credentials must stay false to pair with origins "*".
  allow do
    origins "*"

    resource "/api/v1/catalog/*",
             headers: :any,
             methods: [ :get, :options, :head ],
             credentials: false

    resource "/api/graphql",
             headers: :any,
             methods: [ :post, :options, :head ],
             credentials: false
  end
end

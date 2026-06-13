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
             methods: [:get, :post, :put, :patch, :delete, :options, :head],
             credentials: true,
             expose: ["Authorization"]
  end
end

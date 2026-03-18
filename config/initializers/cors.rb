# frozen_string_literal: true

# config/initializers/cors.rb
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    # Allow localhost and ngrok for development/testing
    # For production, set CORS_ORIGINS environment variable to your frontend URL
    origins_list = [
      "http://localhost:3001",
      "https://localhost:3001",
      /\Ahttps?:\/\/localhost:\d+\z/ # Allow any localhost port
    ]
    if Rails.env.development?
      origins_list << "https://heron-selected-literally.ngrok-free.app"
      origins_list << /\Achrome-extension:\/\/.+\z/ # Allow any Chrome extension in development
    end

    origins(*origins_list)

    resource "/api/*",
             headers: :any,
             methods: [:get, :post, :put, :patch, :delete, :options, :head],
             credentials: true,
             expose: ["Authorization"]
  end
end

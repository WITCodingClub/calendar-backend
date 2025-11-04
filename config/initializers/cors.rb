# frozen_string_literal: true

# config/initializers/cors.rb
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    # Allow localhost and ngrok for development/testing
    # For production, set CORS_ORIGINS environment variable to your frontend URL
    origins "http://localhost:3001",
            "https://localhost:3001",
            "https://heron-selected-literally.ngrok-free.app",
            /\Ahttps?:\/\/localhost:\d+\z/ # Allow any localhost port

    resource "/api/*",
             headers: :any,
             methods: [:get, :post, :put, :patch, :delete, :options, :head],
             credentials: true,
             expose: ["Authorization"]
  end
end

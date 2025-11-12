# config/initializers/console1984.rb
# Configure console1984 to prompt for a username when starting Rails console.

if defined?(Console1984)
  Console1984.configure do |config|
    # Use the gem's documented default resolver: reads ENV["CONSOLE_USER"]
    config.username_resolver = Console1984::Username::EnvResolver.new("CONSOLE_USER")

    # Enable interactive prompt if username is empty
    config.ask_for_username_if_empty = true

    # Optional: limit protection to production only (default is [:production])
    config.protected_environments = %i[production, staging]
  end
end

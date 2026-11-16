# frozen_string_literal: true

require "rails_helper"
require "open3"

# The test environment does not load config/environments/production.rb, so
# this spec boots the production config in a child process (as the Docker asset
# build does, with SECRET_KEY_BASE_DUMMY) and checks the settings it ends up with.
RSpec.describe "Production config" do # rubocop:disable RSpec/DescribeClass
  # rubocop:disable RSpec/BeforeAfterAll -- one production boot for the file
  before(:all) do
    script = <<~RUBY
      config = Rails.application.config
      request = ->(path) { ActionDispatch::Request.new(Rack::MockRequest.env_for(path)) }
      ssl_exclude = config.ssl_options.dig(:redirect, :exclude)
      host_exclude = config.host_authorization[:exclude]
      puts JSON.generate(
        force_ssl: config.force_ssl,
        assume_ssl: config.assume_ssl,
        hosts: config.hosts.map(&:to_s),
        ssl_skips: %w[/up /api].select { |path| ssl_exclude.call(request.(path)) },
        host_check_skips: %w[/up /api].select { |path| host_exclude.call(request.(path)) },
        mailer_url: config.action_mailer.default_url_options,
        controller_url: config.action_controller.default_url_options,
        cache_store: config.cache_store,
        cache_database: SolidCache.configuration.connects_to
      )
    RUBY
    env = { "RAILS_ENV" => "production", "SECRET_KEY_BASE_DUMMY" => "1", "APPLICATION_HOST" => nil }
    output, status = Open3.capture2e(env, "bin/rails", "runner", script, chdir: Rails.root.to_s)
    raise "production boot failed:\n#{output}" unless status.success?

    @production = JSON.parse(output.lines.last)
  end
  # rubocop:enable RSpec/BeforeAfterAll

  let(:production) { @production } # rubocop:disable RSpec/InstanceVariable

  it "forces SSL behind the TLS proxy, except for the health check" do
    expect(production).to include("force_ssl" => true, "assume_ssl" => true, "ssl_skips" => [ "/up" ])
  end

  it "accepts only the public host, except for the health check" do
    expect(production).to include("hosts" => [ "calendar.witcc.dev" ], "host_check_skips" => [ "/up" ])
  end

  # Links built outside a request (meeting links, feed URLs, mail) take their
  # host and protocol from these options. Without the protocol they use http.
  it "builds links outside a request with the public host over https" do
    url = { "host" => "calendar.witcc.dev", "protocol" => "https" }

    expect(production).to include("mailer_url" => url, "controller_url" => url)
  end

  it "keeps Rails.cache in Solid Cache on the cache database" do
    expect(production).to include("cache_store" => "solid_cache_store")
    expect(production["cache_database"]).to eq("shards" => { "cache" => { "writing" => "cache" } })
  end

  # The OAuth callback must use the same public host, or Google sends the
  # user to a host that config.hosts refuses. The initializer builds the
  # callback URL at boot, where this spec cannot read it back, so it reads the file.
  it "builds the Google OAuth callback from the public host" do
    omniauth = Rails.root.join("config/initializers/omniauth.rb").read

    expect(omniauth).to include('"https://#{Rails.configuration.x.application_host}/auth/google_oauth2/callback"')
  end
end

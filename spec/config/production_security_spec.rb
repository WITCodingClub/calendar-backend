# frozen_string_literal: true

require "rails_helper"

# The test environment does not load config/environments/production.rb, so
# these examples read the file, like spec/config/cache_store_spec.rb.
RSpec.describe "Production SSL and host settings" do
  let(:production) { Rails.root.join("config/environments/production.rb").read }

  def active_lines = production.lines.map(&:strip).reject { |line| line.start_with?("#") }

  it "forces SSL behind the TLS proxy" do
    expect(active_lines).to include("config.assume_ssl = true", "config.force_ssl = true")
  end

  it "does not redirect the health check" do
    expect(active_lines).to include(
      'config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }'
    )
  end

  it "accepts only the public host" do
    expect(active_lines).to include('config.hosts = [ ENV.fetch("APPLICATION_HOST", "calendar.witcc.dev") ]')
  end

  it "does not check the host of the health check" do
    expect(active_lines).to include(
      'config.host_authorization = { exclude: ->(request) { request.path == "/up" } }'
    )
  end

  # The same host must build the OAuth callback URL, or Google would send the
  # user to a host that config.hosts refuses.
  it "uses the same host for the Google OAuth callback" do
    omniauth = Rails.root.join("config/initializers/omniauth.rb").read

    expect(omniauth).to include('ENV.fetch("APPLICATION_HOST", "calendar.witcc.dev")')
  end
end

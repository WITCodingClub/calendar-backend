# frozen_string_literal: true

require "rails_helper"

# Middleware matches these paths outside the router, so a route renamed in
# config/routes must change RequestPaths too.
RSpec.describe RequestPaths do
  def routes?(path, method)
    Rails.application.routes.recognize_path(path, method: method)
    true
  rescue ActionController::RoutingError
    false
  end

  it "names paths that the router still draws" do
    expect(routes?(described_class::MCP, :post)).to be(true)
    expect(routes?(described_class::OAUTH_AUTHORIZE, :get)).to be(true)
    described_class::OAUTH_CLIENT.each { |path| expect(routes?(path, :post)).to be(true), path }
    expect(routes?("#{described_class::OAUTH_METADATA_PREFIX}authorization-server", :get)).to be(true)
    expect(routes?("#{described_class::PUBLIC_CATALOG_PREFIX}/terms", :get)).to be(true)
    described_class::GRAPHQL.each { |path| expect(routes?(path, :post)).to be(true), path }
    expect(routes?(described_class::EXTENSION_EVENTS, :post)).to be(true)
    expect(routes?(described_class::CSP_REPORTS, :post)).to be(true)
    expect(routes?("#{described_class::CALENDAR_FEED_PREFIX}abc", :get)).to be(true)
    expect(routes?("#{described_class::MEETING_LINK_PREFIX}abc", :get)).to be(true)
  end
end

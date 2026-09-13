# frozen_string_literal: true

require "rails_helper"

RSpec.describe CloudflareClientIp do
  subject(:middleware) { described_class.new(->(env) { [ 200, {}, [ ActionDispatch::Request.new(env).remote_ip ] ] }) }

  # What Thruster hands to Puma: the docker gateway as the peer, and the
  # address Traefik saw as the last X-Forwarded-For entry.
  def env_for(forwarded_for:, cf_connecting_ip: nil)
    env = Rack::MockRequest.env_for("/", "REMOTE_ADDR" => "172.18.0.1", "HTTP_X_FORWARDED_FOR" => forwarded_for)
    env["HTTP_CF_CONNECTING_IP"] = cf_connecting_ip if cf_connecting_ip
    env
  end

  def client_ip(env)
    middleware.call(env)
    [ Rack::Request.new(env).ip, ActionDispatch::Request.new(env).remote_ip ]
  end

  it "runs before ActionDispatch::RemoteIp and Rack::Attack" do
    stack = Rails.application.middleware.map(&:klass)

    expect(stack.index(described_class)).to be < stack.index(ActionDispatch::RemoteIp)
    expect(stack.index(described_class)).to be < stack.index(Rack::Attack)
  end

  it "uses CF-Connecting-IP for a request from a Cloudflare edge" do
    env = env_for(forwarded_for: "104.22.14.190", cf_connecting_ip: "203.0.113.7")

    expect(client_ip(env)).to eq([ "203.0.113.7", "203.0.113.7" ])
  end

  it "accepts an IPv6 client behind an IPv6 Cloudflare edge" do
    env = env_for(forwarded_for: "2606:4700::1", cf_connecting_ip: "2001:db8::42")

    expect(client_ip(env)).to eq([ "2001:db8::42", "2001:db8::42" ])
  end

  it "ignores CF-Connecting-IP from a client that is not Cloudflare" do
    env = env_for(forwarded_for: "198.51.100.9", cf_connecting_ip: "203.0.113.7")

    expect(client_ip(env)).to eq([ "198.51.100.9", "198.51.100.9" ])
  end

  it "ignores a CF-Connecting-IP value that is not an IP address" do
    env = env_for(forwarded_for: "104.22.14.190", cf_connecting_ip: "not-an-ip")

    expect(client_ip(env)).to eq([ "104.22.14.190", "104.22.14.190" ])
  end

  it "leaves a request without the header unchanged" do
    env = env_for(forwarded_for: "104.22.14.190")

    expect(client_ip(env)).to eq([ "104.22.14.190", "104.22.14.190" ])
  end
end

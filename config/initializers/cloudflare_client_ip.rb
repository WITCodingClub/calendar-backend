# frozen_string_literal: true

require "ipaddr"

# Production sits behind Cloudflare, then Traefik, then Thruster. Traefik does
# not trust the X-Forwarded-For header from Cloudflare, so Rails sees the
# Cloudflare edge address as the client. Rack::Attack then throttles many users
# under one address, and the logs show no real client IPs.
#
# Cloudflare sends the real client address in CF-Connecting-IP. This middleware
# uses it only when the request came from a Cloudflare range, so a client that
# connects directly cannot set its own address.
class CloudflareClientIp
  # https://www.cloudflare.com/ips-v4 and https://www.cloudflare.com/ips-v6 (2026-09-13)
  RANGES = %w[
    173.245.48.0/20 103.21.244.0/22 103.22.200.0/22 103.31.4.0/22
    141.101.64.0/18 108.162.192.0/18 190.93.240.0/20 188.114.96.0/20
    197.234.240.0/22 198.41.128.0/17 162.158.0.0/15 104.16.0.0/13
    104.24.0.0/14 172.64.0.0/13 131.0.72.0/22
    2400:cb00::/32 2606:4700::/32 2803:f800::/32 2405:b500::/32
    2405:8100::/32 2a06:98c0::/29 2c0f:f248::/32
  ].map { |range| IPAddr.new(range) }.freeze

  def self.cloudflare?(address)
    ip = IPAddr.new(address)
    RANGES.any? { |range| range.family == ip.family && range.include?(ip) }
  rescue IPAddr::Error
    false
  end

  def initialize(app)
    @app = app
  end

  def call(env)
    client_ip = env["HTTP_CF_CONNECTING_IP"].to_s.strip

    if client_ip.present? && valid_ip?(client_ip) && self.class.cloudflare?(Rack::Request.new(env).ip)
      env["REMOTE_ADDR"] = client_ip
      env.delete("HTTP_X_FORWARDED_FOR")
      env.delete("HTTP_CLIENT_IP")
    end

    @app.call(env)
  end

  private

  def valid_ip?(address)
    IPAddr.new(address)
    true
  rescue IPAddr::Error
    false
  end
end

# At the top of the stack (Rack::Cors also inserts at 0), so Rack::Attack,
# ActionDispatch::RemoteIp and the request log all see the real client address.
Rails.application.config.middleware.insert_before 0, CloudflareClientIp

# frozen_string_literal: true

class VersionService < ApplicationService
  GITHUB_REPO    = "WITCodingClub/calendar"
  CACHE_KEY      = "version_service/latest_release"
  CACHE_DURATION = 15.minutes

  def call
    {
      current:          current_version,
      current_sha:      current_sha,
      latest:           latest_version,
      update_available: update_available?,
      checked_at:       Time.current
    }
  end

  def call!
    call
  end

  def current_version
    @current_version ||= begin
      version = `git describe --tags --always 2>/dev/null`.strip
      version.presence || current_sha
    end
  end

  def current_sha
    @current_sha ||= begin
      revision_file = Rails.root.join("REVISION")
      if revision_file.exist?
        revision_file.read.strip[0..6]
      else
        `git rev-parse --short HEAD 2>/dev/null`.strip.presence || "unknown"
      end
    end
  end

  def latest_version
    @latest_version ||= Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_DURATION) do
      fetch_latest_release_from_github
    end
  end

  def update_available?
    return false if latest_version.blank?

    current_tag = extract_tag(current_version)
    return false if current_tag.blank?

    Gem::Version.new(normalize_version(latest_version)) > Gem::Version.new(normalize_version(current_tag))
  rescue ArgumentError
    false
  end

  private

  def fetch_latest_release_from_github
    fetch_latest_release || fetch_latest_tag
  end

  def fetch_latest_release
    response = Faraday.get("https://api.github.com/repos/#{GITHUB_REPO}/releases/latest") do |req|
      req.headers["Accept"]     = "application/vnd.github.v3+json"
      req.headers["User-Agent"] = "WIT-Calendar"
      req.options.timeout       = 5
      req.options.open_timeout  = 2
    end

    JSON.parse(response.body)["tag_name"] if response.success?
  rescue Faraday::Error, JSON::ParserError
    nil
  end

  def fetch_latest_tag
    response = Faraday.get("https://api.github.com/repos/#{GITHUB_REPO}/tags") do |req|
      req.headers["Accept"]     = "application/vnd.github.v3+json"
      req.headers["User-Agent"] = "WIT-Calendar"
      req.options.timeout       = 5
      req.options.open_timeout  = 2
    end

    if response.success?
      tags       = JSON.parse(response.body)
      tag_names  = tags.map { |t| t["name"] } # rubocop:disable Rails/Pluck
      semver_tags = tag_names.grep(/\Av?\d+\.\d+\.\d+\z/)
      semver_tags.max_by { |v| Gem::Version.new(normalize_version(v)) }
    end
  rescue Faraday::Error, JSON::ParserError, ArgumentError
    nil
  end

  def extract_tag(version)
    return nil if version.blank?
    return version if version.match?(/\Av?\d+\.\d+\.\d+\z/)

    version.match(/\A(v?\d+\.\d+\.\d+)/)&.[](1)
  end

  def normalize_version(version)
    version.to_s.sub(/\Av/, "")
  end
end

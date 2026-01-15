# frozen_string_literal: true

# Service to check current application version and detect available updates.
# Compares local git version against GitHub releases.
class VersionService < ApplicationService
  GITHUB_REPO = "WITCodingClub/calendar-backend"
  CACHE_KEY = "version_service/latest_release"
  CACHE_DURATION = 15.minutes

  def call
    {
      current: current_version,
      current_sha: current_sha,
      latest: latest_version,
      update_available: update_available?,
      checked_at: Time.current
    }
  end

  def call!
    call
  end

  # Get the current running version from git
  def current_version
    @current_version ||= begin
      # Try to get version from git describe (includes tag info)
      version = `git describe --tags --always 2>/dev/null`.strip
      version.presence || current_sha
    end
  end

  # Get the current commit SHA
  def current_sha
    @current_sha ||= begin
      # In production, use REVISION file if it exists (set during deploy)
      revision_file = Rails.root.join("REVISION")
      if revision_file.exist?
        revision_file.read.strip[0..6]
      else
        `git rev-parse --short HEAD 2>/dev/null`.strip.presence || "unknown"
      end
    end
  end

  # Get the latest release version from GitHub (cached)
  def latest_version
    @latest_version ||= Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_DURATION) do
      fetch_latest_release_from_github
    end
  end

  # Check if an update is available
  def update_available?
    return false if latest_version.blank?

    current_tag = extract_tag(current_version)
    return false if current_tag.blank?

    Gem::Version.new(normalize_version(latest_version)) > Gem::Version.new(normalize_version(current_tag))
  rescue ArgumentError
    # Version parsing failed, assume no update
    false
  end

  private

  def fetch_latest_release_from_github
    # Try releases first, fall back to tags
    fetch_latest_release || fetch_latest_tag
  end

  def fetch_latest_release
    response = Faraday.get("https://api.github.com/repos/#{GITHUB_REPO}/releases/latest") do |req|
      req.headers["Accept"] = "application/vnd.github.v3+json"
      req.headers["User-Agent"] = "WIT-Calendar-Backend"
      req.options.timeout = 5
      req.options.open_timeout = 2
    end

    if response.success?
      data = JSON.parse(response.body)
      data["tag_name"]
    end
  rescue Faraday::Error, JSON::ParserError
    nil
  end

  def fetch_latest_tag
    response = Faraday.get("https://api.github.com/repos/#{GITHUB_REPO}/tags") do |req|
      req.headers["Accept"] = "application/vnd.github.v3+json"
      req.headers["User-Agent"] = "WIT-Calendar-Backend"
      req.options.timeout = 5
      req.options.open_timeout = 2
    end

    if response.success?
      tags = JSON.parse(response.body)
      # Find the latest semver tag
      tag_names = tags.map { |t| t["name"] } # rubocop:disable Rails/Pluck
      semver_tags = tag_names.grep(/\Av?\d+\.\d+\.\d+\z/)
      semver_tags.max_by { |v| Gem::Version.new(normalize_version(v)) }
    end
  rescue Faraday::Error, JSON::ParserError, ArgumentError
    nil
  end

  # Extract the tag portion from git describe output
  # e.g., "v1.0.2-155-ge4a290c" -> "v1.0.2"
  def extract_tag(version)
    return nil if version.blank?

    # If it's a clean tag (e.g., "v1.0.2"), return as-is
    return version if version.match?(/\Av?\d+\.\d+\.\d+\z/)

    # Extract tag from git describe format (e.g., "v1.0.2-155-ge4a290c")
    match = version.match(/\A(v?\d+\.\d+\.\d+)/)
    match&.[](1)
  end

  # Normalize version string for comparison (remove 'v' prefix)
  def normalize_version(version)
    version.to_s.sub(/\Av/, "")
  end

end

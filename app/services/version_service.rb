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

  # The admin layout renders this on every page. The running code does not
  # change until the process restarts, so start git once per process, not once
  # per page.
  def self.current_version
    @current_version ||= `git describe --tags --always 2>/dev/null`.strip.presence || current_sha
  end

  def self.current_sha
    @current_sha ||= revision_from_file || `git rev-parse --short HEAD 2>/dev/null`.strip.presence || "unknown"
  end

  # The production image has no git. The build writes the commit to REVISION.
  def self.revision_from_file
    file = Rails.root.join("REVISION")
    file.read.strip[0..6].presence if file.exist?
  end
  private_class_method :revision_from_file

  def current_version = self.class.current_version
  def current_sha = self.class.current_sha

  # race_condition_ttl lets one request refresh an expired entry while the
  # others keep the old value, so a slow GitHub blocks one page, not every page.
  def latest_version
    @latest_version ||= Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_DURATION, race_condition_ttl: 30.seconds) do
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
    github_get("releases/latest")&.fetch("tag_name", nil)
  end

  def fetch_latest_tag
    tag_names = Array(github_get("tags")).map { |t| t["name"] } # rubocop:disable Rails/Pluck
    tag_names.grep(/\Av?\d+\.\d+\.\d+\z/).max_by { |v| Gem::Version.new(normalize_version(v)) }
  end

  # The parsed JSON body, or nil when GitHub does not answer with a success.
  def github_get(path)
    response = Faraday.get("https://api.github.com/repos/#{GITHUB_REPO}/#{path}") do |req|
      req.headers["Accept"]     = "application/vnd.github.v3+json"
      req.headers["User-Agent"] = "WIT-Calendar"
      req.options.timeout       = 5
      req.options.open_timeout  = 2
    end

    JSON.parse(response.body) if response.success?
  rescue Faraday::Error, JSON::ParserError => e
    Rails.error.report(e, handled: true, context: { path: path })
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

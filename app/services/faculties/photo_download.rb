# frozen_string_literal: true

module Faculties
  # Attaches the directory photo of a professor and stores its URL. Returns
  # true when it attached the photo, false when the download failed (reported),
  # and nil when there was nothing to do.
  class PhotoDownload
    class Error < StandardError; end

    MAX_BYTES = 5.megabytes
    # A directory sync downloads many photos, so a slow photo is skipped, not
    # retried.
    CONNECTION = { open_timeout: 5, timeout: 10, retry_methods: [] }.freeze
    # wit.edu serves the photos and can redirect between its hosts.
    WIT_HOSTS = %w[wit.edu www.wit.edu].freeze

    # The directory shows these images for a person with no photo.
    PLACEHOLDER_WORDS = %w[placeholder Icon_User].freeze

    def self.call(faculty, url) = new(faculty, url).call

    def initialize(faculty, url)
      @faculty = faculty
      @url = url
    end

    def call
      return if @url.blank? || PLACEHOLDER_WORDS.any? { |word| @url.include?(word) }
      return if @faculty.photo_url == @url && @faculty.photo.attached?

      host = URI(@url).host
      return if host.nil?

      body = HttpFetcher.new(allowed_hosts: [ host, *WIT_HOSTS ], error: Error, **CONNECTION).get(@url, max_bytes: MAX_BYTES)
      raise Error, "GET #{@url}: HTTP 404" if body.nil?

      @faculty.photo.attach(io: StringIO.new(body), filename: filename)
      @faculty.update_column(:photo_url, @url) unless @faculty.photo_url == @url # rubocop:disable Rails/SkipsModelValidations
      true
    rescue => e
      Rails.error.report(e, handled: true, context: { faculty_id: @faculty.id })
      false
    end

    private

    def filename
      extension = File.extname(URI(@url).path).presence || ".jpg"
      "#{@faculty.email.split('@').first}_photo#{extension}"
    end
  end
end

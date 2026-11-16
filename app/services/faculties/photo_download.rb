# frozen_string_literal: true

module Faculties
  # Attaches the directory photo of a professor and stores its URL. Returns
  # true when it attached the photo, false when the download failed (reported),
  # and nil when there was nothing to do.
  class PhotoDownload
    class Error < StandardError; end

    MAX_BYTES = 5.megabytes
    TIMEOUT = 10

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

      body = HttpFetcher.new(allowed_hosts: [ URI(@url).host ], error: Error, timeout: TIMEOUT).get(@url, max_bytes: MAX_BYTES)
      raise Error, "GET #{@url}: HTTP 404" if body.nil?

      @faculty.photo.attach(io: StringIO.new(body), filename: filename)
      @faculty.update_column(:photo_url, @url) unless @faculty.photo_url == @url # rubocop:disable Rails/SkipsModelValidations
      true
    rescue Error, URI::Error => e
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

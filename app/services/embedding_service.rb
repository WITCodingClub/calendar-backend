# frozen_string_literal: true

# Turns text into an OpenAI embedding vector.
#
# The catalog stores one vector per section, instructor and review, and search
# embeds the person's query the same way. Both paths call this service, so the
# model and the dimension count can never drift apart. See docs/embeddings.md.
#
# The service is off when OPENAI_API_KEY is missing. Callers ask `configured?`
# first; the jobs and the search paths skip their work instead of raising.
class EmbeddingService
  MODEL      = "text-embedding-3-small"
  DIMENSIONS = 1536

  # text-embedding-3-small takes 8192 tokens per input. One token is about four
  # characters, and every text this app embeds is far shorter, so the cut is a
  # guard against a runaway review, not a normal code path.
  MAX_CHARACTERS = 20_000

  # The API takes up to 2048 inputs per request. A smaller batch keeps one
  # failed request cheap to retry.
  MAX_BATCH_SIZE = 100

  API_URL         = "https://api.openai.com/v1/embeddings"
  REQUEST_TIMEOUT = 30

  class Error < StandardError; end
  class ConfigurationError < Error; end
  class ApiError < Error; end

  class << self
    def configured?
      api_key.present?
    end

    def api_key
      ENV["OPENAI_API_KEY"].presence
    end
  end

  # @param text [String, nil]
  # @return [Array<Float>, nil] nil when the text is blank
  def embed(text)
    embed_all([ text ]).first
  end

  # One request per MAX_BATCH_SIZE texts. Blank texts get no vector, and the
  # returned array keeps the order and length of the input, so a caller can zip
  # it back onto its records.
  #
  # @param texts [Array<String, nil>]
  # @return [Array<Array<Float>, nil>]
  def embed_all(texts)
    inputs = Array(texts).map { |text| prepare(text) }
    return inputs if inputs.compact.empty?

    vectors = Array.new(inputs.length)

    inputs.each_with_index.reject { |text, _| text.nil? }.each_slice(MAX_BATCH_SIZE) do |slice|
      request(slice.map(&:first)).each_with_index do |vector, offset|
        vectors[slice[offset].last] = vector
      end
    end

    vectors
  end

  private

  def prepare(text)
    return nil if text.blank?

    text.to_s.strip.truncate(MAX_CHARACTERS)
  end

  def request(inputs)
    raise ConfigurationError, "OPENAI_API_KEY is not set" unless self.class.configured?

    response = connection.post do |req|
      req.body = { model: MODEL, input: inputs, dimensions: DIMENSIONS }
    end

    raise ApiError, "OpenAI returned #{response.status}: #{error_message(response)}" unless response.success?

    vectors = response.body.fetch("data", []).sort_by { |row| row["index"] }.map { |row| row["embedding"] }
    raise ApiError, "OpenAI returned #{vectors.length} vectors for #{inputs.length} inputs" if vectors.length != inputs.length

    vectors
  rescue Faraday::Error => e
    raise ApiError, "OpenAI request failed: #{e.message}"
  end

  def connection
    @connection ||= Faraday.new(url: API_URL) do |f|
      f.request :json
      f.request :retry, max: 2, interval: 1, backoff_factor: 2,
                retry_statuses: [ 429, 500, 502, 503, 504 ],
                exceptions: [ Faraday::TimeoutError, Faraday::ConnectionFailed ]
      f.response :json
      f.headers["Authorization"] = "Bearer #{self.class.api_key}"
      f.options.timeout      = REQUEST_TIMEOUT
      f.options.open_timeout = 10
    end
  end

  def error_message(response)
    body = response.body
    return body.dig("error", "message") if body.is_a?(Hash)

    body.to_s.truncate(200)
  end
end

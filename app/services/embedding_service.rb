# frozen_string_literal: true

class EmbeddingService
  DEFAULT_MODEL = "text-embedding-3-small"
  DIMENSIONS = 1536

  class Error < StandardError; end
  class ConfigurationError < Error; end
  class ApiError < Error; end

  def initialize(model: DEFAULT_MODEL)
    @model = model
    @client = build_client
  end

  # Generate embedding for a single text
  # @param text [String] The text to embed
  # @return [Array<Float>] The embedding vector (1536 dimensions)
  def generate(text)
    return nil if text.blank?

    response = @client.embeddings(
      parameters: {
        model: @model,
        input: text.truncate(8000), # OpenAI has token limits
        dimensions: DIMENSIONS
      }
    )

    response.dig("data", 0, "embedding")
  rescue Faraday::Error => e
    Rails.logger.error("[EmbeddingService] API request failed: #{e.message}")
    raise ApiError, "Failed to generate embedding: #{e.message}"
  end

  # Generate embeddings for multiple texts in a single API call
  # @param texts [Array<String>] Array of texts to embed
  # @return [Array<Array<Float>>] Array of embedding vectors
  def generate_batch(texts)
    return [] if texts.blank?

    # Filter out blank texts and track their indices
    valid_texts = []
    valid_indices = []

    texts.each_with_index do |text, index|
      next if text.blank?

      valid_texts << text.truncate(8000)
      valid_indices << index
    end

    return Array.new(texts.length) if valid_texts.empty?

    response = @client.embeddings(
      parameters: {
        model: @model,
        input: valid_texts,
        dimensions: DIMENSIONS
      }
    )

    # Build result array with nils for blank inputs
    result = Array.new(texts.length)
    response["data"].each do |item|
      original_index = valid_indices[item["index"]]
      result[original_index] = item["embedding"]
    end

    result
  rescue Faraday::Error => e
    Rails.logger.error("[EmbeddingService] Batch API request failed: #{e.message}")
    raise ApiError, "Failed to generate batch embeddings: #{e.message}"
  end

  # Generate and save embedding for a record
  # @param record [ApplicationRecord] Record with embedding column and embedding_text method
  # @return [Boolean] Whether the embedding was saved successfully
  def embed_record(record)
    unless record.respond_to?(:embedding_text)
      Rails.logger.warn("[EmbeddingService] Record #{record.class.name}##{record.id} does not respond to embedding_text")
      return false
    end

    text = record.embedding_text
    return false if text.blank?

    embedding = generate(text)
    return false if embedding.nil?

    # rubocop:disable Rails/SkipsModelValidations -- Intentionally skip callbacks to avoid infinite loops
    record.update_column(:embedding, embedding)
    # rubocop:enable Rails/SkipsModelValidations
    Rails.logger.info("[EmbeddingService] Generated embedding for #{record.class.name}##{record.id}")
    true
  rescue ApiError => e
    Rails.logger.error("[EmbeddingService] Failed to embed #{record.class.name}##{record.id}: #{e.message}")
    false
  end

  # Generate and save embeddings for multiple records
  # @param records [Array<ApplicationRecord>] Records with embedding column and embedding_text method
  # @return [Integer] Number of records successfully embedded
  def embed_records(records)
    return 0 if records.empty?

    texts = records.map do |record|
      record.respond_to?(:embedding_text) ? record.embedding_text : nil
    end

    embeddings = generate_batch(texts)

    success_count = 0
    records.each_with_index do |record, index|
      embedding = embeddings[index]
      next if embedding.nil?

      # rubocop:disable Rails/SkipsModelValidations -- Intentionally skip callbacks to avoid infinite loops
      record.update_column(:embedding, embedding)
      # rubocop:enable Rails/SkipsModelValidations
      success_count += 1
    end

    Rails.logger.info("[EmbeddingService] Generated #{success_count}/#{records.length} embeddings for #{records.first.class.name}")
    success_count
  rescue ApiError => e
    Rails.logger.error("[EmbeddingService] Batch embedding failed: #{e.message}")
    0
  end

  private

  def build_client
    api_key = Rails.application.credentials.dig(:openai, :api_key) || ENV.fetch("OPENAI_API_KEY", nil)

    if api_key.blank?
      raise ConfigurationError, "OpenAI API key not configured. Set credentials.openai.api_key or OPENAI_API_KEY env var."
    end

    OpenAI::Client.new(access_token: api_key)
  end

end

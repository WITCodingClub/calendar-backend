# frozen_string_literal: true

class GenerateEmbeddingJob < ApplicationJob
  queue_as :default

  # Retry on API errors with exponential backoff
  retry_on EmbeddingService::ApiError, wait: :polynomially_longer, attempts: 5
  retry_on Faraday::Error, wait: :polynomially_longer, attempts: 5

  # Don't retry on configuration errors
  discard_on EmbeddingService::ConfigurationError

  # Generate embedding for a single record
  # @param record_type [String] Class name of the record (e.g., "Course")
  # @param record_id [Integer] ID of the record
  def perform(record_type, record_id)
    record = record_type.constantize.find_by(id: record_id)

    unless record
      Rails.logger.warn("[GenerateEmbeddingJob] Record not found: #{record_type}##{record_id}")
      return
    end

    service = EmbeddingService.new
    service.embed_record(record)
  end

end

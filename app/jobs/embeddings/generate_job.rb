# frozen_string_literal: true

module Embeddings
  # Embeds one batch of records.
  #
  # The job takes ids rather than a scope, so a retry embeds the same rows and
  # nothing is skipped when another job writes in between. Rows whose text has
  # not changed since the last run cost nothing: they never reach the API.
  class GenerateJob < ApplicationJob
    queue_as :low

    MODELS = %w[Course Faculty RmpRating].freeze

    retry_on Embeddings::Generator::ApiError, wait: :polynomially_longer, attempts: 5
    discard_on Embeddings::Generator::ConfigurationError

    # @param model_name [String] one of MODELS
    # @param ids [Array<Integer>]
    def perform(model_name, ids)
      unless MODELS.include?(model_name)
        Rails.logger.error("[Embeddings::GenerateJob] Unknown model #{model_name.inspect}")
        return
      end

      return unless Embeddings::Generator.configured?

      records = model_name.constantize.where(id: ids).select(&:embedding_stale?)
      return if records.empty?

      texts   = records.map(&:embedding_text)
      vectors = Embeddings::Generator.new.embed_all(texts)

      written = records.each_with_index.count do |record, index|
        record.store_embedding(vectors[index], text: texts[index])
      end

      Rails.logger.info("[Embeddings::GenerateJob] Embedded #{written} #{model_name} record(s)")
    end
  end
end

# frozen_string_literal: true

module Embeddings
  # Embeds one batch of records.
  #
  # The job takes ids rather than a scope, so a retry embeds the same rows and
  # nothing is skipped when another job writes in between. Rows whose text has
  # not changed since the last run cost nothing: they never reach the API.
  class GenerateJob < ApplicationJob
    queue_as :low

    MODELS = %w[CatalogCourse Faculty RmpRating].freeze

    # Solid Queue puts this string in every lock key, so it must never change.
    CONCURRENCY_GROUP = "EmbeddingsGenerateJob"

    # Two backfills can queue the same ids: the catalog details batch starts
    # one, and the 11am fallback is another. One job at a time for each model
    # means the second job checks embedding_stale? after the first one wrote
    # the vector, so the same text never reaches the API twice. A batch of 100
    # takes seconds, so 10 minutes is a large margin.
    limits_concurrency to: 1, group: CONCURRENCY_GROUP, key: ->(model_name, *) { "embeddings_#{model_name}" },
                       duration: 10.minutes

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

      records = Embeddings::BackfillJob::SCOPES.fetch(model_name).call.where(id: ids).select(&:embedding_stale?)
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

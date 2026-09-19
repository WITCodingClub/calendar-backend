# frozen_string_literal: true

# Finds the records whose vector is missing or out of date and hands them to
# GenerateEmbeddingsJob in batches.
#
# It runs nightly, after the catalog sync writes the new sections, and it is
# safe to run by hand at any time. A record that has not changed is skipped
# before it reaches the API, so a second run costs one scan and no money.
class BackfillEmbeddingsJob < ApplicationJob
  queue_as :low

  BATCH_SIZE = EmbeddingService::MAX_BATCH_SIZE

  # Reviews are the largest table by far, so they come last.
  SCOPES = {
    "Course"    => -> { Course.active },
    "Faculty"   => -> { Faculty.with_courses },
    "RmpRating" => -> { RmpRating.where.not(comment: [ nil, "" ]) }
  }.freeze

  # @param model_name [String, nil] one model, or nil for all of them
  def perform(model_name = nil)
    unless EmbeddingService.configured?
      Rails.logger.info("[BackfillEmbeddingsJob] OPENAI_API_KEY is not set; nothing to do")
      return
    end

    names = model_name ? [ model_name ] : SCOPES.keys
    names.each { |name| enqueue_batches(name) }
  end

  private

  def enqueue_batches(model_name)
    scope = SCOPES.fetch(model_name) { raise ArgumentError, "Unknown model #{model_name.inspect}" }.call

    stale = 0

    scope.find_in_batches(batch_size: BATCH_SIZE) do |records|
      ids = records.select(&:embedding_stale?).map(&:id)
      next if ids.empty?

      stale += ids.length
      GenerateEmbeddingsJob.perform_later(model_name, ids)
    end

    Rails.logger.info("[BackfillEmbeddingsJob] Queued #{stale} #{model_name} record(s)")
  end
end

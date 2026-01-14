# frozen_string_literal: true

# Concern for models that support vector embeddings
# Include this in models that have an `embedding` column and `embedding_text` method
#
# Usage:
#   class Course < ApplicationRecord
#     include Embeddable
#     # Define embedding_text method that returns text to embed
#   end
#
module Embeddable
  extend ActiveSupport::Concern

  included do
    # Automatically generate embedding when record is created or relevant fields change
    after_commit :enqueue_embedding_generation, on: [:create, :update], if: :should_generate_embedding?

    scope :with_embeddings, -> { where.not(embedding: nil) }
    scope :without_embeddings, -> { where(embedding: nil) }
  end

  # Queue a job to generate embedding for this record
  def enqueue_embedding_generation
    GenerateEmbeddingJob.perform_later(self.class.name, id)
  end

  # Generate embedding synchronously (useful for console/testing)
  def generate_embedding!
    EmbeddingService.new.embed_record(self)
  end

  # Check if the embedding needs to be regenerated
  def embedding_stale?
    embedding.nil? || embedding_text_changed?
  end

  private

  # Determine if we should generate a new embedding
  # Override in model if you want custom logic
  def should_generate_embedding?
    return false unless respond_to?(:embedding_text)
    return false if embedding_text.blank?

    # Generate on create, or when embedding_text would have changed
    embedding.nil? || embedding_text_fields_changed?
  end

  # Check if any fields that affect embedding_text have changed
  # Models can override this for custom behavior
  def embedding_text_fields_changed?
    # Default: check if any saved changes exist that could affect embedding
    # This is a conservative approach - models can override for precision
    saved_changes.keys.any? { |key| key != "embedding" && key != "updated_at" }
  end
end

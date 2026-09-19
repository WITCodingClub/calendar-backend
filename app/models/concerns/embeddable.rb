# frozen_string_literal: true

# Shared behaviour for the models that carry an embedding column.
#
# A model that includes this defines `embedding_text`, the sentence that stands
# for the record. The concern keeps the vector in step with that text: it
# stores the SHA256 of the text next to the vector, so a backfill re-embeds
# only the rows whose text changed.
#
# Writes go through update_columns. An embedding is derived data, so it must
# not touch updated_at and must not fire the callbacks that mark a student's
# calendar as out of date.
module Embeddable
  extend ActiveSupport::Concern

  included do
    has_neighbors :embedding

    scope :embedded,     -> { where.not(embedding: nil) }
    scope :not_embedded, -> { where(embedding: nil) }
  end

  class_methods do
    # The rows closest to a query vector, nearest first.
    #
    # @param vector [Array<Float>]
    # @param limit [Integer]
    # @return [ActiveRecord::Relation]
    def nearest_to(vector, limit: 20)
      return none if vector.blank?

      embedded.nearest_neighbors(:embedding, vector, distance: "cosine").limit(limit)
    end

    def digest_for(text)
      Digest::SHA256.hexdigest(text.to_s)
    end
  end

  # The text that stands for this record. Every including model defines it.
  def embedding_text
    raise NotImplementedError, "#{self.class.name} must define #embedding_text"
  end

  # True when the row has no vector, or when the text has changed since the
  # vector was made.
  def embedding_stale?
    text = embedding_text
    return false if text.blank?

    embedding.nil? || embedding_digest != self.class.digest_for(text)
  end

  # @param vector [Array<Float>, nil]
  def store_embedding(vector, text: embedding_text)
    return false if vector.blank?

    update_columns(embedding: vector, embedding_digest: self.class.digest_for(text)) # rubocop:disable Rails/SkipsModelValidations
  end

  # The records closest to this one, itself excluded.
  def similar(limit: 10)
    return self.class.none if embedding.nil?

    self.class.nearest_to(embedding, limit: limit).where.not(id: id)
  end
end

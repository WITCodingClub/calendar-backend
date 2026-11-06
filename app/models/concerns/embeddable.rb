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

  # How many neighbours a "what is like this?" request returns, and the most
  # it may ask for. Both the API and the GraphQL schema read these.
  DEFAULT_SIMILAR_LIMIT = 10
  MAX_SIMILAR_LIMIT     = 50

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

    # The ids of the rows closest to the vector, nearest first.
    #
    # The filters go inside the vector query, so they run before the cut. The
    # query runs with an iterative index scan (see with_iterative_scan), so a
    # filter that drops most rows still fills the limit.
    #
    # @param among [ActiveRecord::Relation, nil] a select of the ids allowed
    # @param except [Integer, nil] an id to leave out
    # @return [Array<Integer>]
    def nearest_ids(vector, limit:, among: nil, except: nil)
      return [] if vector.blank?

      relation = nearest_to(vector, limit: limit)
      relation = relation.where(id: among) if among
      relation = relation.where.not(id: except) if except
      with_iterative_scan { relation.pluck(:id) }
    end

    # The ids of the rows in `scope` closest to the vector, nearest first.
    # Catalog::SemanticSearch calls it. Course has its own version, because
    # its vector lives on CatalogCourse.
    #
    # @return [Array<Integer>]
    def ids_nearest_to(vector, scope:, limit:)
      nearest_ids(vector, limit: limit, among: scope.unscope(:order).select(:id))
    end

    # An HNSW index scan reads hnsw.ef_search rows (40 by default), and the
    # filters run after it. A filter such as "has a section this term" can
    # drop all 40, and the query then returns fewer rows than the limit, or
    # none. An iterative scan keeps reading the index until the limit is full.
    # strict_order keeps the rows in exact distance order. It needs pgvector
    # 0.8 (docker/postgres/Dockerfile).
    #
    # SET LOCAL lasts until the transaction ends, so the setting does not
    # reach other queries on the connection.
    def with_iterative_scan(&)
      transaction do
        connection.execute("SET LOCAL hnsw.iterative_scan = strict_order")
        yield
      end
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

  # The records closest to this one, itself excluded, nearest first.
  #
  # @param among [ActiveRecord::Relation, nil] a select of the ids allowed
  def similar(limit: DEFAULT_SIMILAR_LIMIT, among: nil)
    return self.class.none if embedding.nil?

    ids = self.class.nearest_ids(embedding, limit: limit, among: among, except: id)
    self.class.where(id: ids).in_order_of(:id, ids)
  end
end

# frozen_string_literal: true

module Catalog
  # Turns a person's words into the vector the catalog searches by.
  #
  # Keyword search finds the sections that contain the words. Semantic search
  # finds the sections that mean the same thing, so "intro to programming"
  # reaches "Computer Science I". Both are offered: a CRN or a course number is
  # still best matched literally.
  #
  # Every query costs an API call, so vectors are cached by the text itself.
  # Students ask the same few questions during registration, and the cache
  # turns the repeats into no call at all.
  module SemanticSearch
    CACHE_PREFIX = "catalog/semantic_search/v1"
    CACHE_TTL    = 1.day

    # How many rows the vector search returns before the other filters run.
    # One full page is 200 rows, so a page is never short because of this cap.
    CANDIDATE_LIMIT = ::Catalog::SectionQuery::MAX_PER_PAGE

    module_function

    # Semantic search needs a key to embed the query and a flag to say it is
    # wanted. Without either, callers fall back to keyword search.
    def available?
      EmbeddingService.configured? && Flipper.enabled?(FlipperFlags::SEMANTIC_SEARCH)
    end

    # @param query [String]
    # @return [Array<Float>, nil] nil when search is off or the API failed
    def vector_for(query)
      return nil unless available?

      text = query.to_s.strip
      return nil if text.blank?

      Rails.cache.fetch(cache_key(text), expires_in: CACHE_TTL) do
        EmbeddingService.new.embed(text)
      end
    rescue EmbeddingService::Error => e
      # A search that returns the keyword results is better than a search that
      # returns an error, so the caller gets nil and falls back.
      Rails.logger.warn("[SemanticSearch] #{e.class}: #{e.message}")
      nil
    end

    # The rows of `scope` that mean what the query means, nearest first.
    #
    # @param scope [ActiveRecord::Relation] a relation of an Embeddable model
    # @param query [String]
    # @return [ActiveRecord::Relation, nil] nil when the caller should fall
    #   back to keyword search
    def ranked_scope(scope, query, limit: CANDIDATE_LIMIT)
      vector = vector_for(query)
      return nil if vector.blank?

      ids = ranked_ids(scope, vector, limit: limit)
      return scope.none if ids.empty?

      scope.where(id: ids).in_order_of(:id, ids)
    end

    # The ids of the rows in `scope` closest to the vector, nearest first.
    #
    # The scope goes inside the vector query, so filters such as the term are
    # applied before the cut rather than after it.
    #
    # @return [Array<Integer>]
    def ranked_ids(scope, vector, limit: CANDIDATE_LIMIT)
      scope.model.nearest_to(vector, limit: limit)
           .where(id: scope.unscope(:order).select(:id))
           .pluck(:id)
    end

    def cache_key(text)
      "#{CACHE_PREFIX}/#{Digest::SHA256.hexdigest(text.downcase)}"
    end
  end
end

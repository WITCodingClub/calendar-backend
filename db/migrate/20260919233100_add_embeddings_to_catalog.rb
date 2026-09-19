# frozen_string_literal: true

# Embedding columns for the three records people search: sections, instructors
# and reviews. embedding_digest holds the SHA256 of the text that produced the
# vector, so a backfill re-embeds only the rows whose text changed.
#
# The HNSW indexes use cosine distance, which is what OpenAI recommends for
# text-embedding-3-small. An empty table builds them in milliseconds.
class AddEmbeddingsToCatalog < ActiveRecord::Migration[8.1]
  DIMENSIONS = 1536

  TABLES = %i[courses faculties rmp_ratings].freeze

  def change
    TABLES.each do |table|
      add_column table, :embedding, :vector, limit: DIMENSIONS
      add_column table, :embedding_digest, :string, limit: 64

      add_index table, :embedding, using: :hnsw, opclass: :vector_cosine_ops,
                name: "index_#{table}_on_embedding"
    end
  end
end

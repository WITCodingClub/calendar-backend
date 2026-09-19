# frozen_string_literal: true

# pgvector stores the embedding columns that back semantic search.
# See docs/embeddings.md for the Postgres image that ships the extension.
class EnableVectorExtension < ActiveRecord::Migration[8.1]
  def change
    enable_extension "vector"
  end
end

# frozen_string_literal: true

# The vector that stands for a course moves from each section to the course
# itself. Every section of COMP 2350 teaches the same thing, so one vector per
# course is enough, and the catalog now has the description and the learning
# objectives that say what the course teaches (docs/embeddings.md).
#
# courses.embedding stays for now. Course ignores it, and a later migration
# drops it.
class AddEmbeddingToCatalogCourses < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  DIMENSIONS = 1536

  def change
    add_column :catalog_courses, :embedding, :vector, limit: DIMENSIONS
    add_column :catalog_courses, :embedding_digest, :string, limit: 64

    add_index :catalog_courses, :embedding, using: :hnsw, opclass: :vector_cosine_ops,
              name: "index_catalog_courses_on_embedding", algorithm: :concurrently
  end
end

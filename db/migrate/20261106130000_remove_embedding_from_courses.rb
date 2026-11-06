# frozen_string_literal: true

# The course vector lives on catalog_courses since
# 20261106120000_add_embedding_to_catalog_courses. courses.embedding was never
# filled in production: the embedding backfill never ran there.
class RemoveEmbeddingFromCourses < ActiveRecord::Migration[8.1]
  DIMENSIONS = 1536

  def change
    # strong_migrations wants Course to ignore these columns in a deploy before
    # this one. The columns hold no data, and the new Course does not know them.
    # The old container still lists them in each INSERT, so a section created
    # in the few seconds between this migration and the slot swap fails. Only
    # Courses::Processor creates sections outside the nightly import, and a
    # student can run it again.
    safety_assured do
      remove_index :courses, :embedding, using: :hnsw, opclass: :vector_cosine_ops,
                                         name: "index_courses_on_embedding"
      remove_column :courses, :embedding, :vector, limit: DIMENSIONS
      remove_column :courses, :embedding_digest, :string, limit: 64
    end
  end
end

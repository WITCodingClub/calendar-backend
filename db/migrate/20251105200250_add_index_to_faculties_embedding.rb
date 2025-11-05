class AddIndexToFacultiesEmbedding < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    # Skip index creation - HNSW requires data with dimensions
    # Will add index later after embeddings are generated
    # add_index :faculties, :embedding, using: :hnsw, opclass: :vector_cosine_ops, algorithm: :concurrently
  end
end

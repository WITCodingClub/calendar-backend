class AddEmbeddingToFaculties < ActiveRecord::Migration[8.1]
  def change
    add_column :faculties, :embedding, :vector, limit: 1536
  end
end

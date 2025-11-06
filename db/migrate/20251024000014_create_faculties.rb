class CreateFaculties < ActiveRecord::Migration[8.0]
  def change
    create_table :faculties do |t|
      t.string :first_name, null: false
      t.string :last_name, null: false
      t.string :email, null: false
      t.vector :embedding, limit: 1536
      t.timestamps
    end

    add_index :faculties, :email, unique: true
    # Note: HNSW index for embedding will be added after data is populated
  end
end
# frozen_string_literal: true

# The production cache database can already exist with only schema_migrations.
# bin/rails db:prepare loads db/cache_schema.rb only into a database without
# schema_migrations, so this migration creates the table in that case. A fresh
# database gets the table from db/cache_schema.rb, and the checks below skip it.
class CreateSolidCacheEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :solid_cache_entries, if_not_exists: true do |t|
      t.binary :key, limit: 1024, null: false
      t.binary :value, limit: 536870912, null: false
      t.datetime :created_at, null: false
      t.integer :key_hash, limit: 8, null: false
      t.integer :byte_size, limit: 4, null: false
    end

    add_index :solid_cache_entries, :byte_size, if_not_exists: true
    add_index :solid_cache_entries, [ :key_hash, :byte_size ], if_not_exists: true
    add_index :solid_cache_entries, :key_hash, unique: true, if_not_exists: true
  end
end

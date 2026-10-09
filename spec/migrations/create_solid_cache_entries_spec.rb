# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/cache_migrate/20261008000000_create_solid_cache_entries")

# The cache database only exists in production. It can already exist there
# with only schema_migrations, because config/database.yml had the cache entry
# before db/cache_schema.rb existed. db:prepare does not load a schema into a
# database that has schema_migrations, so this migration creates the table.
# These examples run it inside the test transaction on the test database.
RSpec.describe CreateSolidCacheEntries do
  subject(:migration) { build_migration }

  let(:connection) { ActiveRecord::Base.connection }

  before { migration.verbose = false }

  it "creates the table that db/cache_schema.rb defines" do
    migration.migrate(:up)

    columns = connection.columns(:solid_cache_entries).to_h { |column| [ column.name, column ] }
    expect(columns.keys).to contain_exactly("id", "key", "value", "created_at", "key_hash", "byte_size")
    expect(columns["key_hash"].sql_type).to eq("bigint")
    expect(columns["byte_size"].sql_type).to eq("integer")
    expect(columns.values_at("key", "value", "created_at", "key_hash", "byte_size").map(&:null)).to all(be(false))
    expect(connection.index_exists?(:solid_cache_entries, :key_hash, unique: true)).to be(true)
    expect(connection.index_exists?(:solid_cache_entries, [ :key_hash, :byte_size ])).to be(true)
    expect(connection.index_exists?(:solid_cache_entries, :byte_size)).to be(true)
  end

  it "is safe to run on a database that db/cache_schema.rb already loaded" do
    migration.migrate(:up)

    expect { migration.migrate(:up) }.not_to raise_error
  end

  it "is the version that db/cache_schema.rb records, so a fresh load skips it" do
    schema = Rails.root.join("db/cache_schema.rb").read

    expect(schema).to include("define(version: 2026_10_08_000000)")
  end
end

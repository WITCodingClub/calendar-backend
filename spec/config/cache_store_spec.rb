# frozen_string_literal: true

require "rails_helper"

# Production keeps Rails.cache in Solid Cache. The test environment uses a null
# store, so these examples check the files that production reads at boot and
# at deploy (bin/rails db:prepare loads db/cache_schema.rb).
RSpec.describe "Solid Cache configuration" do
  it "uses the solid cache store in production" do
    production = Rails.root.join("config/environments/production.rb").read

    expect(production).to match(/^\s*config\.cache_store = :solid_cache_store$/)
  end

  it "puts the production cache in the cache database from config/database.yml" do
    cache_config = ActiveSupport::ConfigurationFile.parse(Rails.root.join("config/cache.yml"))
    database_config = ActiveSupport::ConfigurationFile.parse(Rails.root.join("config/database.yml"))

    expect(cache_config.dig("production", "database")).to eq("cache")
    expect(database_config.dig("production", "cache", "migrations_paths")).to eq("db/cache_migrate")
  end

  it "ships the schema that db:prepare loads into the cache database" do
    schema = Rails.root.join("db/cache_schema.rb").read

    expect(schema).to include('create_table "solid_cache_entries"')
  end

  # Solid Cache raises NotImplementedError on delete_matched. A call in app
  # code would pass in test (null store) and fail only in production.
  it "has no delete_matched call in app code" do
    callers = Rails.root.glob("{app,lib,config}/**/*.rb").select do |path|
      path.read.lines.any? { |line| line.match?(/\.delete_matched\b/) && !line.strip.start_with?("#") }
    end

    expect(callers).to be_empty
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe "strong_migrations" do # rubocop:disable RSpec/DescribeClass
  # A migration that strong_migrations rejects: it removes a column that the
  # running app may still read.
  let(:unsafe_migration) do
    Class.new(ActiveRecord::Migration[8.1]) do
      def change
        remove_column :courses_faculties, :primary_indicator
      end
    end
  end

  it "checks every migration after the last one that ran before the gem" do
    expect(StrongMigrations.start_after).to eq(20261008223000)
  end

  it "checks against the PostgreSQL version that production runs" do
    expect(StrongMigrations.target_version).to eq(17)
  end

  it "sets lock and statement timeouts for migrations" do
    expect(StrongMigrations.lock_timeout).to eq(10.seconds)
    expect(StrongMigrations.statement_timeout).to eq(1.hour)
  end

  it "stops an unsafe migration" do
    migration = unsafe_migration.new("UnsafeRemoveColumn", 20261009210000)
    migration.verbose = false

    expect { migration.migrate(:up) }.to raise_error(StrongMigrations::UnsafeMigration)
  end
end

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

  # Migrations before start_after ran before the gem; production runs
  # PostgreSQL 17; the timeouts keep a migration from holding locks while the
  # old container still serves (docs/deploy.md).
  it "checks new migrations against production's PostgreSQL with lock and statement timeouts" do
    expect(StrongMigrations).to have_attributes(start_after: 20261008223000, target_version: 17,
                                                lock_timeout: 10.seconds, statement_timeout: 1.hour)
  end

  it "stops an unsafe migration" do
    migration = unsafe_migration.new("UnsafeRemoveColumn", 20261009210000)
    migration.verbose = false

    expect { migration.migrate(:up) }.to raise_error(StrongMigrations::UnsafeMigration)
  end
end

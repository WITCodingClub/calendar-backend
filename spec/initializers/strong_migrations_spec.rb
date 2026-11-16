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

  it "stops an unsafe migration" do
    migration = unsafe_migration.new("UnsafeRemoveColumn", 20261009210000)
    migration.verbose = false

    expect { migration.migrate(:up) }.to raise_error(StrongMigrations::UnsafeMigration)
  end
end

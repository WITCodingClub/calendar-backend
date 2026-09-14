# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/queue_migrate/20260913000000_add_batches_to_solid_queue")

# The queue database only exists in production. The test database gets the
# pre-1.7 solid_queue_jobs table from db/schema.rb, and these examples migrate
# it inside the test transaction. The table is built here if it is missing.
RSpec.describe AddBatchesToSolidQueue do
  subject(:migration) { described_class.new }

  let(:connection) { ActiveRecord::Base.connection }

  before do
    migration.verbose = false
    connection.create_table :solid_queue_jobs, if_not_exists: true do |t|
      t.string :queue_name, null: false
      t.string :class_name, null: false
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
    end
  end

  it "adds batch tracking to an existing queue database" do
    migration.migrate(:up)

    # Postgres reports bigint columns with type :integer, so compare the SQL type.
    expect(connection.columns(:solid_queue_jobs).find { |column| column.name == "batch_id" }&.sql_type).to eq("bigint")
    expect(connection.index_exists?(:solid_queue_jobs, :batch_id)).to be(true)
    expect(connection.index_exists?(:solid_queue_batches, :active_job_batch_id, unique: true)).to be(true)
    expect(connection.index_exists?(:solid_queue_batch_executions, :job_id, unique: true)).to be(true)
    expect(connection.foreign_key_exists?(:solid_queue_batch_executions, :solid_queue_batches, column: :batch_id)).to be(true)
    expect(connection.foreign_key_exists?(:solid_queue_batch_executions, :solid_queue_jobs, column: :job_id)).to be(true)
  end

  it "is safe to run again" do
    migration.migrate(:up)

    expect { migration.migrate(:up) }.not_to raise_error
  end

  it "is the version db/queue_schema.rb records, so fresh installs skip it" do
    latest = Rails.root.glob("db/queue_migrate/*.rb").map { |path| path.basename.to_s.to_i }.max
    schema_version = Rails.root.join("db/queue_schema.rb").read[/define\(version: ([\d_]+)\)/, 1].delete("_").to_i

    expect(schema_version).to eq(latest)
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec::Matchers.define_negated_matcher :not_change, :change

RSpec.describe ImportFromBackendService do
  # The legacy database is a raw PG connection. PG::Result rows are hashes of
  # strings, so the fake returns the same shape. Unmatched queries get no rows.
  let(:legacy_rows) do
    {
      /FROM flipper_features/ => [ { "key" => "legacy_beta" } ],
      /FROM flipper_gates/ => [
        { "feature_key" => "legacy_beta", "key" => "boolean", "value" => "true" },
        { "feature_key" => "legacy_beta", "key" => "actors", "value" => "User;O'Brien" }
      ],
      /FROM blazer_queries/ => [
        { "id" => "7", "name" => nil, "description" => "Robert'); DROP TABLE users;--",
          "statement" => "SELECT 1", "data_source" => "main", "status" => "active", "creator_id" => nil }
      ],
      /FROM blazer_dashboards/ => [ { "id" => "3", "name" => "Ops", "creator_id" => nil } ],
      /FROM blazer_dashboard_queries/ => [ { "dashboard_id" => "3", "query_id" => "7", "position" => "2" } ],
      /FROM blazer_checks/ => [
        { "query_id" => "7", "creator_id" => nil, "check_type" => "bad_data", "emails" => "ops@example.com",
          "schedule" => "1 hour", "slack_channels" => nil, "state" => "passing",
          "last_run_at" => "2026-01-02 03:04:05" }
      ]
    }
  end

  let(:conn) do
    instance_double(PG::Connection, close: nil).tap do |fake|
      allow(fake).to receive(:exec) do |sql|
        legacy_rows.find { |pattern, _| sql.match?(pattern) }&.last || []
      end
    end
  end

  before do
    allow(PG).to receive(:connect).and_return(conn)
    allow($stdout).to receive(:puts)
    allow($stdout).to receive(:write)
  end

  def import(dry_run: false)
    described_class.call(database_url: "postgresql://legacy.invalid/backend", dry_run: dry_run)
  end

  describe "Flipper migration" do
    it "copies features and gates, and keeps quotes in values" do
      import

      expect(Flipper::Adapters::ActiveRecord::Feature.where(key: "legacy_beta")).to exist
      expect(Flipper::Adapters::ActiveRecord::Gate.where(feature_key: "legacy_beta").pluck(:key, :value))
        .to contain_exactly([ "boolean", "true" ], [ "actors", "User;O'Brien" ])
    end

    it "skips features and gates that already exist" do
      import

      expect { import }
        .to not_change(Flipper::Adapters::ActiveRecord::Feature, :count)
        .and not_change(Flipper::Adapters::ActiveRecord::Gate, :count)
    end
  end

  describe "Blazer migration" do
    it "copies queries, dashboards, and checks with the new ids" do
      import

      query = Blazer::Query.sole
      expect(query).to have_attributes(name: "", description: "Robert'); DROP TABLE users;--", statement: "SELECT 1")

      dashboard = Blazer::Dashboard.sole
      expect(dashboard.name).to eq("Ops")
      expect(Blazer::DashboardQuery.sole).to have_attributes(dashboard_id: dashboard.id, query_id: query.id, position: 2)
      expect(Blazer::Check.sole).to have_attributes(
        query_id: query.id, check_type: "bad_data", state: "passing",
        last_run_at: Time.utc(2026, 1, 2, 3, 4, 5)
      )
    end
  end

  it "writes nothing in a dry run" do
    expect { import(dry_run: true) }
      .to not_change(Flipper::Adapters::ActiveRecord::Gate, :count)
      .and not_change(Blazer::Query, :count)
      .and not_change(Blazer::Check, :count)
  end
end

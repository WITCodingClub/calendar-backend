# frozen_string_literal: true

require "rails_helper"

# Issue #686: the nightly sync reads only users with calendar_needs_sync set,
# so the index holds only those rows. The migration builds indexes
# concurrently, which cannot run inside the test transaction, so these
# examples check the schema that the migration leaves.
RSpec.describe "Partial index on users.calendar_needs_sync" do # rubocop:disable RSpec/DescribeClass
  let(:connection) { ActiveRecord::Base.connection }

  it "replaces the full boolean index with a partial index" do
    indexes = connection.indexes(:users).index_by(&:name)

    expect(indexes).not_to have_key("index_users_on_calendar_needs_sync")
    expect(indexes["index_users_needing_calendar_sync"]).to have_attributes(
      columns: [ "calendar_needs_sync" ], where: "calendar_needs_sync"
    )
  end

  it "lets the planner use the partial index for the needs_sync flag" do
    # The test table is small, so the planner prefers a sequential scan
    # unless it is turned off for this transaction. The needs_sync scope also
    # joins the calendars (#911), and on a small table the planner can pick
    # the primary key for that join instead, so this checks the flag alone.
    connection.execute("SET LOCAL enable_seqscan = off")

    expect(User.where(calendar_needs_sync: true).explain.inspect).to include("index_users_needing_calendar_sync")
  end
end

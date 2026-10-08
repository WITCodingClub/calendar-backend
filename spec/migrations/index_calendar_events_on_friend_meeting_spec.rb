# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261007100310_index_calendar_events_on_friend_meeting")

# calendar_events is large, so its indexes must not lock writes during the
# build. CREATE INDEX CONCURRENTLY cannot run in a transaction, so this group
# runs outside the test transaction and puts the indexes back itself.
RSpec.describe IndexCalendarEventsOnFriendMeeting do
  self.use_transactional_tests = false

  subject(:migration) { described_class.new }

  let(:connection) { ActiveRecord::Base.connection }
  let(:names)      { described_class::INDEXES.keys }

  before { migration.verbose = false }

  after { migration.up unless names.all? { |name| valid_index?(name) } }

  def valid_index?(name)
    connection.select_value(<<~SQL.squish) == true
      SELECT pg_index.indisvalid FROM pg_index
      JOIN pg_class ON pg_class.oid = pg_index.indexrelid
      WHERE pg_class.relname = #{connection.quote(name)}
    SQL
  end

  it "runs outside a transaction, so the indexes can be built concurrently" do
    expect(described_class.disable_ddl_transaction).to be(true)
  end

  it "builds both indexes, and runs again after an index was left behind" do
    migration.down
    connection.add_index :calendar_events, :friend_meeting_id, name: names.first

    migration.up

    expect(names.map { |name| valid_index?(name) }).to eq([ true, true ])
  end

  it "replaces an INVALID index that a failed concurrent build left" do
    connection.execute(<<~SQL.squish)
      UPDATE pg_index SET indisvalid = false
      WHERE indexrelid = #{connection.quote(names.last)}::regclass
    SQL

    migration.up

    expect(valid_index?(names.last)).to be(true)
  end
end

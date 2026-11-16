# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261007100310_index_calendar_events_on_friend_meeting")

# calendar_events is large, so its indexes must not lock writes during the
# build. CREATE INDEX CONCURRENTLY cannot run in a transaction, so this group
# runs outside the test transaction. It runs the migration on an empty copy of
# calendar_events in its own schema, first in the search path, so the real
# table and its indexes stay as they are for every other spec.
RSpec.describe IndexCalendarEventsOnFriendMeeting do
  self.use_transactional_tests = false

  subject(:migration) { build_migration }

  let(:connection) { ActiveRecord::Base.connection }
  let(:names)      { described_class::INDEXES.keys }

  let(:schema) { "migration_spec_#{Process.pid}" }

  before do
    migration.verbose = false
    connection.execute(<<~SQL)
      DROP SCHEMA IF EXISTS #{schema} CASCADE;
      CREATE SCHEMA #{schema};
      CREATE TABLE #{schema}.calendar_events (LIKE public.calendar_events INCLUDING DEFAULTS);
      ALTER TABLE #{schema}.calendar_events ADD FOREIGN KEY (friend_meeting_id)
        REFERENCES public.friend_meetings (id) NOT VALID;
    SQL
    @search_path = connection.schema_search_path
    connection.schema_search_path = "#{schema}, #{@search_path}"
  end

  after do
    connection.schema_search_path = @search_path
    connection.execute("DROP SCHEMA IF EXISTS #{schema} CASCADE")
    connection.schema_cache.clear!
  end

  def valid_index?(name)
    connection.select_value(<<~SQL.squish) == true
      SELECT pg_index.indisvalid FROM pg_index
      JOIN pg_class ON pg_class.oid = pg_index.indexrelid
      WHERE pg_class.relname = #{connection.quote(name)} AND pg_class.relnamespace = #{connection.quote(schema)}::regnamespace
    SQL
  end

  it "builds both indexes, and runs again after an index was left behind" do
    connection.add_index :calendar_events, :friend_meeting_id, name: names.first

    migration.up

    expect(names.map { |name| valid_index?(name) }).to eq([ true, true ])
  end

  it "replaces an INVALID index that a failed concurrent build left" do
    migration.up
    connection.execute(<<~SQL.squish)
      UPDATE pg_index SET indisvalid = false
      WHERE indexrelid = '#{schema}.#{names.last}'::regclass
    SQL

    migration.up

    expect(valid_index?(names.last)).to be(true)
  end
end

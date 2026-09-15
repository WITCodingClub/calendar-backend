# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260914120000_generalize_calendars_for_multiple_providers")

# The test database is already at this migration. Each example rolls it back
# inside the test transaction, builds rows in the old tables by hand, and runs
# it again. Postgres DDL is transactional, so the rollback at the end of the
# example restores the schema.
RSpec.describe GeneralizeCalendarsForMultipleProviders do
  subject(:migration) { described_class.new }

  let(:connection) { ActiveRecord::Base.connection }

  before { migration.verbose = false }

  after do
    connection.schema_cache.clear!
    [ CourseCalendar, CalendarEvent, EventPreference, OauthCredential ].each(&:reset_column_information)
  end

  def insert(sql)
    connection.select_value(sql)
  end

  def index_names(table)
    connection.indexes(table).map(&:name)
  end

  # users and oauth_credentials are not changed by this migration.
  def build_credential
    user = User.create!(email: "migration-#{SecureRandom.hex(4)}@wit.edu", password: "correct horse battery staple",
                        confirmed_at: Time.current)
    insert(<<~SQL)
      INSERT INTO oauth_credentials (user_id, provider, uid, email, access_token, created_at, updated_at)
      VALUES (#{user.id}, 'google', 'uid-#{SecureRandom.hex(4)}', '#{user.email}', 'synthetic-token', NOW(), NOW())
      RETURNING id
    SQL
  end

  def build_old_rows
    credential_id = build_credential
    user_id       = insert("SELECT user_id FROM oauth_credentials WHERE id = #{credential_id}")
    calendar_id   = insert(<<~SQL)
      INSERT INTO google_calendars (oauth_credential_id, google_calendar_id, summary, created_at, updated_at)
      VALUES (#{credential_id}, 'old-cal@group.calendar.google.com', 'WIT Courses', NOW(), NOW())
      RETURNING id
    SQL
    event_id = insert(<<~SQL)
      INSERT INTO google_calendar_events (google_calendar_id, google_event_id, university_calendar_event_id, created_at, updated_at)
      VALUES (#{calendar_id}, 'old-event-1', 1, NOW(), NOW())
      RETURNING id
    SQL
    insert(<<~SQL)
      INSERT INTO event_preferences (user_id, preferenceable_type, preferenceable_id, created_at, updated_at)
      VALUES (#{user_id}, 'GoogleCalendarEvent', #{event_id}, NOW(), NOW())
      RETURNING id
    SQL

    { calendar_id: calendar_id, event_id: event_id }
  end

  it "moves the Google tables to provider-neutral names and keeps every row" do
    migration.migrate(:down)
    ids = build_old_rows

    migration.migrate(:up)

    expect(connection.table_exists?(:google_calendars)).to be(false)
    expect(connection.table_exists?(:google_calendar_events)).to be(false)
    expect(connection.select_one("SELECT external_calendar_id, provider FROM calendars WHERE id = #{ids[:calendar_id]}"))
      .to eq("external_calendar_id" => "old-cal@group.calendar.google.com", "provider" => "google")
    expect(connection.select_one("SELECT calendar_id, external_event_id, external_ical_uid FROM calendar_events WHERE id = #{ids[:event_id]}"))
      .to eq("calendar_id" => ids[:calendar_id], "external_event_id" => "old-event-1", "external_ical_uid" => nil)
    expect(insert("SELECT preferenceable_type FROM event_preferences WHERE preferenceable_id = #{ids[:event_id]}"))
      .to eq("CalendarEvent")
  end

  it "makes the external calendar id unique per provider and leaves no Google index names" do
    migration.migrate(:down)
    migration.migrate(:up)

    expect(connection.index_exists?(:calendars, [ :provider, :external_calendar_id ], unique: true)).to be(true)
    expect(connection.index_exists?(:calendars, :external_calendar_id, unique: true)).to be(false)
    expect(connection.index_exists?(:calendar_events, :external_ical_uid)).to be(true)
    expect(index_names(:calendars) + index_names(:calendar_events)).to all(satisfy { |name| !name.match?(/google|gcal/) })
  end

  it "rolls back to the Google tables" do
    migration.migrate(:down)
    ids = build_old_rows
    migration.migrate(:up)

    migration.migrate(:down)

    expect(connection.table_exists?(:calendars)).to be(false)
    expect(insert("SELECT google_calendar_id FROM google_calendars WHERE id = #{ids[:calendar_id]}"))
      .to eq("old-cal@group.calendar.google.com")
    expect(insert("SELECT google_event_id FROM google_calendar_events WHERE id = #{ids[:event_id]}")).to eq("old-event-1")
    expect(insert("SELECT preferenceable_type FROM event_preferences WHERE preferenceable_id = #{ids[:event_id]}"))
      .to eq("GoogleCalendarEvent")
    expect(connection.index_exists?(:google_calendars, :google_calendar_id, unique: true)).to be(true)
    expect(index_names(:google_calendar_events)).to include("idx_gcal_events_unique_meeting_time", "idx_on_google_calendar_id_meeting_time_id")
    expect(index_names(:google_calendars)).to include("index_google_calendars_on_oauth_credential_id_unique")
  end

  it "refuses to roll back while a Microsoft calendar exists" do
    credential_id = build_credential
    insert(<<~SQL)
      INSERT INTO calendars (oauth_credential_id, external_calendar_id, provider, created_at, updated_at)
      VALUES (#{credential_id}, 'AAMkSyntheticCalendar1', 'microsoft', NOW(), NOW())
      RETURNING id
    SQL

    expect { migration.migrate(:down) }.to raise_error(ActiveRecord::IrreversibleMigration)
    expect(connection.table_exists?(:calendars)).to be(true)
  end
end

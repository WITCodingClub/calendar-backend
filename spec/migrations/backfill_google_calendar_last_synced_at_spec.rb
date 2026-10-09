# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261008223000_backfill_google_calendar_last_synced_at")

RSpec.describe BackfillGoogleCalendarLastSyncedAt do
  subject(:migration) { build_migration }

  let(:connection) { ActiveRecord::Base.connection }
  let(:synced_at) { Time.zone.local(2026, 10, 7, 12, 0, 0) }

  before { migration.verbose = false }

  def insert_calendar(provider: "google", last_synced_at: nil)
    credential = create(:oauth_credential, provider: provider)
    connection.select_value(<<~SQL.squish)
      INSERT INTO calendars (oauth_credential_id, external_calendar_id, provider, last_synced_at, created_at, updated_at)
      VALUES (#{credential.id}, #{connection.quote(SecureRandom.hex(16))}, #{connection.quote(provider)},
              #{connection.quote(last_synced_at)}, NOW(), NOW())
      RETURNING id
    SQL
  end

  def insert_event(calendar_id, last_synced_at)
    connection.execute(<<~SQL.squish)
      INSERT INTO calendar_events (calendar_id, external_event_id, last_synced_at, created_at, updated_at)
      VALUES (#{calendar_id}, #{connection.quote(SecureRandom.hex(8))}, #{connection.quote(last_synced_at)}, NOW(), NOW())
    SQL
  end

  def last_synced_at_of(calendar_id)
    connection.select_value("SELECT last_synced_at FROM calendars WHERE id = #{calendar_id}")
  end

  it "copies the latest event sync time to a Google calendar with none" do
    calendar_id = insert_calendar
    insert_event(calendar_id, synced_at - 1.day)
    insert_event(calendar_id, synced_at)

    migration.migrate(:up)

    expect(last_synced_at_of(calendar_id)).to eq(synced_at)
  end

  it "keeps a sync time that is already set" do
    calendar_id = insert_calendar(last_synced_at: synced_at + 1.hour)
    insert_event(calendar_id, synced_at)

    migration.migrate(:up)

    expect(last_synced_at_of(calendar_id)).to eq(synced_at + 1.hour)
  end

  it "leaves a calendar with no synced events unset" do
    calendar_id = insert_calendar
    insert_event(calendar_id, nil)

    migration.migrate(:up)

    expect(last_synced_at_of(calendar_id)).to be_nil
  end

  it "leaves Outlook calendars alone" do
    calendar_id = insert_calendar(provider: "microsoft")
    insert_event(calendar_id, synced_at)

    migration.migrate(:up)

    expect(last_synced_at_of(calendar_id)).to be_nil
  end
end

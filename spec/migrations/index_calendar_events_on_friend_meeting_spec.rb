# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261007100310_index_calendar_events_on_friend_meeting")

# calendar_events is large, so its indexes must not lock writes during the
# build.
RSpec.describe IndexCalendarEventsOnFriendMeeting do
  it "runs outside a transaction, so the indexes can be built concurrently" do
    expect(described_class.disable_ddl_transaction).to be(true)
  end

  it "builds every calendar_events index concurrently" do
    source = Rails.root.join("db/migrate/20261007100310_index_calendar_events_on_friend_meeting.rb").read

    expect(source.scan("add_index :calendar_events").size).to eq(2)
    expect(source.scan("algorithm: :concurrently").size).to eq(2)
  end

  it "leaves the indexes in the schema" do
    names = ActiveRecord::Base.connection.indexes(:calendar_events).map(&:name)

    expect(names).to include("index_calendar_events_on_friend_meeting_id", "idx_calendar_events_unique_friend_meeting")
  end
end

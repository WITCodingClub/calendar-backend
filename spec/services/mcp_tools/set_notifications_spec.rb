# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpTools::SetNotifications do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }

  def call(**arguments) = described_class.call(server_context: mcp_context(user), **arguments)

  it "needs the notifications:write scope" do
    result = described_class.call(server_context: mcp_context(user, scopes: %w[catalog settings:write]), disabled: true)

    expect(result.error?).to be(true)
    expect(user.reload.notifications_disabled?).to be(false)
  end

  it "pauses reminders for a number of hours" do
    freeze_time do
      result = call(disabled: true, duration_hours: 1.5)

      expect(result.structured_content).to eq(notifications_disabled: true, notifications_disabled_until: 90.minutes.from_now)
    end
  end

  it "pauses reminders until they are turned on again" do
    call(disabled: true)

    expect(user.reload.notifications_disabled?).to be(true)
    expect(user.notifications_disabled_until).to be > 50.years.from_now
  end

  it "refuses a duration that is not positive or is too long" do
    expect(call(disabled: true, duration_hours: 0).error?).to be(true)
    expect(call(disabled: true, duration_hours: described_class::MAX_HOURS + 1).error?).to be(true)
    expect(user.reload.notifications_disabled?).to be(false)
  end

  it "turns reminders on again and queues a sync to put them back" do
    user.disable_notifications!

    expect { call(disabled: false) }.to have_enqueued_job(CourseCalendars::SyncJob).with(user, force: true)

    expect(user.reload).to have_attributes(notifications_disabled?: false, calendar_needs_sync: true)
  end
end

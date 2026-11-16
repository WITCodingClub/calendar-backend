# frozen_string_literal: true

require "rails_helper"

RSpec.describe Notifications::Toggle do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }

  it "turns the reminders off until they are turned on again" do
    described_class.call(user, disabled: true)

    expect(user.reload.notifications_disabled_until).to be > 50.years.from_now
  end

  it "turns the reminders off for a duration" do
    freeze_time do
      described_class.call(user, disabled: true, duration: 2.hours)

      expect(user.reload.notifications_disabled_until).to eq(2.hours.from_now)
    end
  end

  it "turns the reminders on again" do
    user.disable_notifications!

    described_class.call(user, disabled: false)

    expect(user.reload.notifications_disabled?).to be(false)
  end

  [ true, false ].each do |disabled|
    it "marks the calendar for a sync and queues one (disabled: #{disabled})" do
      expect { described_class.call(user, disabled: disabled) }
        .to have_enqueued_job(CourseCalendars::SyncJob).with(user, force: true)

      expect(user.reload.calendar_needs_sync).to be(true)
    end
  end
end

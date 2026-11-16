# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoogleCalendar::CalendarListJob do
  include ActiveSupport::Testing::TimeHelpers

  let(:user)    { create(:user) }
  let(:manager) { instance_double(GoogleCalendar::CalendarManager) }

  before { allow(GoogleCalendar::CalendarManager).to receive(:new).with(user).and_return(manager) }

  it "adds the calendar to the account's list" do
    allow(manager).to receive(:add_to_calendar_list)

    described_class.perform_now(user, "cal-1", "person@example.test")

    expect(manager).to have_received(:add_to_calendar_list).with("cal-1", "person@example.test")
  end

  it "tries again 20 seconds later while the account cannot see the calendar" do
    allow(manager).to receive(:add_to_calendar_list).and_raise(GoogleCalendar::CalendarManager::NotListableYetError)

    freeze_time do
      expect { described_class.perform_now(user, "cal-1", "person@example.test") }
        .to have_enqueued_job(described_class).with(user, "cal-1", "person@example.test").at(20.seconds.from_now)
    end
  end
end

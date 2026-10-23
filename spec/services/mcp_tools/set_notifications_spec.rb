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

  describe "confirmation" do
    def confirmed_call(context = {}, **arguments)
      described_class.call(server_context: mcp_modern_context(user, **context), **arguments)
    end

    def message(**arguments) = confirmed_call(**arguments).input_requests.dig(McpTools::Confirmation::KEY, :params, :message)

    it "says what changes and what is on now, and changes nothing" do
      expect(message(disabled: true, duration_hours: 1.5)).to eq(
        "Turn off the reminders of all your calendar events for 1 hour and 30 minutes.\nNow: the reminders are on."
      )
      expect(message(disabled: true, duration_hours: 1)).to start_with("Turn off the reminders of all your calendar events for 1 hour.")
      expect(message(disabled: true)).to start_with("Turn off the reminders of all your calendar events until you turn them on again.")
      expect(user.reload.notifications_disabled?).to be(false)
    end

    it "names the end of a pause in Eastern time" do
      user.update!(notifications_disabled_until: Time.zone.parse("2026-10-22 18:30 UTC"))

      travel_to(Time.zone.parse("2026-10-22 12:00 UTC")) do
        expect(message(disabled: false)).to eq(
          "Turn the reminders of all your calendar events on again.\n" \
          "Now: the reminders are off until October 22, 2026 at 2:30 PM (Eastern time)."
        )
      end
    end

    it "does not ask to turn on reminders that are on" do
      expect(confirmed_call(disabled: false).structured_content).to eq(notifications_disabled: false, notifications_disabled_until: nil)
    end

    it "pauses on accept and gives the current state on decline" do
      question = confirmed_call(disabled: true)
      answer = ->(action) { confirmed_call({ input_responses: mcp_confirmation(action), request_state: question.request_state }, disabled: true) }

      declined = answer.call("decline").structured_content
      expect(declined).to include(notifications_disabled: false, notifications_disabled_until: nil, not_changed: include(reason: "declined"))
      expect(user.reload.notifications_disabled?).to be(false)

      expect(answer.call("accept").structured_content).to include(notifications_disabled: true)
      expect(user.reload.notifications_disabled?).to be(true)
    end

    it "checks the duration before it asks" do
      expect(confirmed_call(disabled: true, duration_hours: 0).error?).to be(true)
      expect(confirmed_call(disabled: true, duration_hours: 0.001).content.first[:text]).to include("at least one minute")
    end

    it "says the duration that it stores, in whole minutes" do
      freeze_time do
        expect(message(disabled: true, duration_hours: 0.01)).to start_with("Turn off the reminders of all your calendar events for 1 minute.")

        call(disabled: true, duration_hours: 0.01)
        expect(user.reload.notifications_disabled_until).to eq(1.minute.from_now)
      end
    end

    it "does not take the same answer again after a pause and a resume" do
      state  = confirmed_call(disabled: true).request_state
      answer = -> { confirmed_call({ input_responses: mcp_confirmation("accept"), request_state: state }, disabled: true) }

      answer.call
      travel(1.second) { call(disabled: false) }

      expect(answer.call).to be_a(MCP::Server::InputRequiredResult)
      expect(user.reload.notifications_disabled?).to be(false)
    end
  end
end

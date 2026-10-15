# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpTools::MyCalendarSettings do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }

  def call = described_class.call(server_context: mcp_context(user))

  it "lists the levels, the classes with their own settings, and the choices" do
    create(:calendar_preference, user: user, scope: :global, color_id: "#039be5")
    create(:calendar_preference, user: user, scope: :event_type, event_type: "laboratory", title_template: "Lab")
    create(:calendar_preference, user: user, scope: :uni_cal_category, event_type: "holiday", color_id: "#d50000")
    create(:calendar_preference, scope: :global, color_id: "#8e24aa")
    course       = create(:course, title: "Physics", term: create(:term, uid: 202610))
    meeting_time = create(:course_meeting_time, course: course)
    create(:event_preference, user: user, preferenceable: meeting_time, color_id: "#f6bf26")

    data = call.structured_content

    expect(data[:levels].map { |level| level[:level] }).to match_array(%w[all_classes laboratory university:holiday])
    expect(data[:levels].find { |level| level[:level] == "laboratory" }).to include(title_template: "Lab")
    expect(data[:classes]).to contain_exactly(hash_including(meeting_time_id: meeting_time.public_id, course: "Physics",
                                                             term_uid: 202610, color_id: "#f6bf26"))
    expect(data[:notifications_disabled_until]).to be_nil
    expect(data[:colors]).to eq(GoogleCalendar::Colors::NAMES)
    expect(data[:template_variables]).to eq(Preferences::TemplateRenderer::ALLOWED_VARIABLES)
  end

  it "says until when reminders are paused" do
    freeze_time do
      user.disable_notifications!(duration: 2.hours)

      expect(call.structured_content[:notifications_disabled_until]).to eq(2.hours.from_now)
    end
  end

  it "needs the settings:read scope" do
    expect(described_class.call(server_context: mcp_context(user, scopes: %w[catalog])).error?).to be(true)
  end
end

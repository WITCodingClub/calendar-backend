# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpTools::UpdateCalendarSettings do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }

  def call(**arguments) = described_class.call(server_context: mcp_context(user), **arguments)

  it "needs the settings:write scope" do
    result = described_class.call(server_context: mcp_context(user, scopes: %w[catalog]), level: "all_classes", color: "sage")

    expect(result.error?).to be(true)
    expect(CalendarPreference.count).to eq(0)
  end

  it "saves the settings of every class" do
    result = call(level: "all_classes", color: "sage", visibility: "private", reminders: [])

    expect(result.structured_content).to include(level: "all_classes", result: :saved)
    expect(CalendarPreference.sole).to have_attributes(scope: "global", event_type: nil, color_id: GoogleCalendar::Colors::SAGE,
                                                       visibility: "private", reminder_settings: [])
  end

  it "maps each level to the preference scope of the API" do
    call(level: "laboratory", color: "banana")
    call(level: "final_exam", title_template: "Final: {{title}}")
    call(level: "university", color: "graphite")
    call(level: "university:holiday", color: "tomato")

    expect(CalendarPreference.find_by(scope: :event_type, event_type: "laboratory").color_id).to eq(GoogleCalendar::Colors::BANANA)
    expect(CalendarPreference.find_by(scope: :event_type, event_type: "final_exam").title_template).to eq("Final: {{title}}")
    expect(CalendarPreference.find_by(scope: :uni_cal_global).color_id).to eq(GoogleCalendar::Colors::GRAPHITE)
    expect(CalendarPreference.find_by(scope: :uni_cal_category, event_type: "holiday").color_id).to eq(GoogleCalendar::Colors::TOMATO)
  end

  it "refuses an unknown level" do
    result = call(level: "weekends", color: "sage")

    expect(result.error?).to be(true)
    expect(result.content.first[:text]).to include("level must be one of all_classes")
  end

  it "resets a field and deletes the row when nothing is left" do
    create(:calendar_preference, user: user, scope: :event_type, event_type: "lecture", color_id: "#039be5", visibility: "public")

    expect(call(level: "lecture", reset: [ "visibility" ]).structured_content[:settings]).to include(visibility: nil, color_id: "#039be5")
    expect(call(level: "lecture", reset: [ "color" ]).structured_content).to include(result: :deleted, settings: nil)
    expect(CalendarPreference.count).to eq(0)
  end

  it "queues a calendar sync for a user with a Microsoft calendar" do
    create(:course_calendar, :microsoft, user: user)

    expect { call(level: "all_classes", color: "sage") }.to have_enqueued_job(CourseCalendars::SyncJob).with(user, force: true)
  end
end

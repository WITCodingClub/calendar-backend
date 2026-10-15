# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpTools::UpdateClassSettings do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }
  let(:course) { create(:course, title: "Data Structures") }
  let(:meeting_time) { create(:course_meeting_time, course: course) }

  before { create(:enrollment, user: user, course: course) }

  def call(**arguments)
    described_class.call(server_context: mcp_context(user), meeting_time_id: meeting_time.public_id, **arguments)
  end

  it "needs the settings:write scope" do
    result = described_class.call(server_context: mcp_context(user, scopes: %w[catalog settings:read]),
                                  meeting_time_id: meeting_time.public_id, color: "tomato")

    expect(result.error?).to be(true)
    expect(EventPreference.count).to eq(0)
  end

  it "creates the class's settings and gives the resolved result with a preview" do
    result = call(title_template: "{{title}} class", color: "tomato", reminders: [ { time: 10, type: "minutes", method: "notification" } ])

    data = result.structured_content
    expect(data).to include(meeting_time_id: meeting_time.public_id, course: "Data Structures", result: :saved)
    expect(data[:class_settings]).to include(title_template: "{{title}} class", color_id: GoogleCalendar::Colors::TOMATO)
    expect(data[:class_settings][:reminder_settings]).to eq([ { "time" => "10", "type" => "minutes", "method" => "notification" } ])
    expect(data[:preview][:title]).to eq("Data Structures class")
    expect(data[:sources][:title_template]).to eq("individual")
  end

  it "changes only the fields passed" do
    create(:event_preference, user: user, preferenceable: meeting_time, title_template: "Keep me", color_id: "#039be5")

    call(color: "3")

    expect(EventPreference.sole).to have_attributes(title_template: "Keep me", color_id: GoogleCalendar::Colors::GRAPE)
  end

  it "takes a color by name, id, or hex, and refuses anything else" do
    expect(call(color: "Peacock").structured_content.dig(:class_settings, :color_id)).to eq(GoogleCalendar::Colors::PEACOCK)
    expect(call(color: "11").structured_content.dig(:class_settings, :color_id)).to eq(GoogleCalendar::Colors::TOMATO)
    expect(call(color: "#ABCDEF").structured_content.dig(:class_settings, :color_id)).to eq("#abcdef")

    result = call(color: "sparkle")
    expect(result.error?).to be(true)
    expect(result.content.first[:text]).to include('"sparkle" is not a color', "tomato")
  end

  it "resets a field so the level below applies, and deletes the row when nothing is left" do
    # An empty reminder list is a setting ("no reminders"), so this row has none.
    create(:event_preference, user: user, preferenceable: meeting_time, title_template: "Mine", color_id: "#039be5", reminder_settings: nil)

    expect(call(reset: [ "title_template" ]).structured_content[:class_settings]).to include(title_template: nil, color_id: "#039be5")
    expect(call(reset: [ "color" ]).structured_content).to include(result: :deleted, class_settings: nil)
    expect(EventPreference.count).to eq(0)
  end

  it "refuses a call with nothing to change" do
    result = call

    expect(result.error?).to be(true)
    expect(result.content.first[:text]).to eq("Pass at least one setting or reset.")
  end

  it "does not find a meeting time of a course the user does not take" do
    other = create(:course_meeting_time)

    result = described_class.call(server_context: mcp_context(user), meeting_time_id: other.public_id, color: "sage")

    expect(result.error?).to be(true)
    expect(result.content.first[:text]).to include("No class meeting #{other.public_id}")
  end

  it "gives the model's validation message for a bad template" do
    result = call(title_template: "{{secret}}")

    expect(result.error?).to be(true)
    expect(result.content.first[:text]).to include("Disallowed variables: secret")
  end

  it "queues no calendar sync for a user with no synced calendar" do
    expect { call(color: "sage") }.not_to have_enqueued_job(CourseCalendars::SyncJob)
  end

  it "queues a calendar sync for a user with a Google calendar" do
    create(:oauth_credential, user: user)

    expect { call(color: "basil") }.to have_enqueued_job(CourseCalendars::SyncJob).with(user, force: true)
  end
end

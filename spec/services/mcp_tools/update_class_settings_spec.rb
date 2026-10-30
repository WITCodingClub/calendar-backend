# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpTools::UpdateClassSettings do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

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

  it "refuses an unknown argument next to a valid setting and changes nothing" do
    result = call(color: "tomato", colour: "grape")

    expect(result.error?).to be(true)
    expect(result.content.first[:text]).to start_with("Unknown argument colour.")
    expect(EventPreference.count).to eq(0)
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

  describe "confirmation" do
    let(:arguments) { { meeting_time_id: meeting_time.public_id, color: "sage", reminders: [], reset: [ "title_template" ] } }

    before do
      create(:event_preference, user: user, preferenceable: meeting_time, title_template: "Old {{title}}", color_id: GoogleCalendar::Colors::PEACOCK)
    end

    def confirmed_call(**context)
      described_class.call(server_context: mcp_modern_context(user, **context), **arguments)
    end

    def question = confirmed_call
    def message = question.input_requests.dig(McpTools::Confirmation::KEY, :params, :message)

    it "asks with the class and each field from the old value to the new one, and changes nothing" do
      expect { question }.not_to have_enqueued_job(CourseCalendars::SyncJob)

      expect(message).to start_with("Change the calendar events of one class only (Data Structures")
      # The factory row has no reminders already, so reminders: [] is no change.
      expect(message.lines.map(&:chomp).drop(1)).to eq([
        "- Color: from Peacock to Sage.",
        '- Event title: from "Old {{title}}" to not set.'
      ])
      expect(EventPreference.sole).to have_attributes(title_template: "Old {{title}}", color_id: GoogleCalendar::Colors::PEACOCK)
    end

    it "makes the change when the student accepts" do
      result = confirmed_call(input_responses: mcp_confirmation("accept"), request_state: question.request_state)

      expect(result.structured_content).to include(result: :saved)
      expect(result.structured_content).not_to have_key(:not_changed)
      expect(EventPreference.sole).to have_attributes(title_template: nil, color_id: GoogleCalendar::Colors::SAGE, reminder_settings: [])
    end

    it "changes nothing and gives the current settings when the student declines" do
      result = confirmed_call(input_responses: mcp_confirmation("decline"), request_state: question.request_state)

      expect(result.error?).to be(false)
      expect(result.structured_content).to include(result: :unchanged, not_changed: { reason: "declined", message: McpTools::BaseWriteTool::NOT_CHANGED_MESSAGE })
      expect(result.structured_content[:class_settings]).to include(title_template: "Old {{title}}")
      expect(EventPreference.sole.color_id).to eq(GoogleCalendar::Colors::PEACOCK)
    end

    it "gives null class settings on a decline when the class has none" do
      EventPreference.delete_all

      result = confirmed_call(input_responses: mcp_confirmation("cancel"), request_state: question.request_state)

      expect(result.structured_content).to include(result: :unchanged, class_settings: nil)
      expect(result.structured_content.dig(:not_changed, :reason)).to eq("cancelled")
      expect(EventPreference.count).to eq(0)
    end

    it "does not ask when nothing changes" do
      result = described_class.call(server_context: mcp_modern_context(user), meeting_time_id: meeting_time.public_id, color: "peacock")

      expect(result.structured_content).to include(result: :saved)
    end

    it "checks the scope and the arguments before it asks" do
      no_scope = described_class.call(server_context: mcp_modern_context(user, scopes: %w[catalog]), **arguments)
      bad_color = described_class.call(server_context: mcp_modern_context(user), meeting_time_id: meeting_time.public_id, color: "sparkle")

      expect([ no_scope, bad_color ]).to all(be_a(MCP::Tool::Response).and(have_attributes(error?: true)))
    end

    it "refuses a template that cannot be saved before it asks, and keeps the row" do
      result = described_class.call(server_context: mcp_modern_context(user), meeting_time_id: meeting_time.public_id,
                                    title_template: "{{secret}}")

      expect(result).to be_a(MCP::Tool::Response)
      expect(result.content.first[:text]).to include("Disallowed variables: secret")
      expect(EventPreference.sole.title_template).to eq("Old {{title}}")
    end

    it "shows a template on one line, escaped and cut, after the other fields" do
      long = "Line one\nLine two \"quoted\" #{'x' * 200}"
      result = described_class.call(server_context: mcp_modern_context(user), meeting_time_id: meeting_time.public_id,
                                    description_template: long, visibility: "private")
      message = result.input_requests.dig(McpTools::Confirmation::KEY, :params, :message)
      lines = message.lines.map(&:chomp)

      expect(lines.size).to eq(3)
      expect(lines[1]).to eq("- Visibility: from not set to private.")
      expect(lines[2]).to start_with('- Event description: from not set to "Line one\nLine two \"quoted\" xxx')
      expect(lines[2]).to end_with('x..."' + ".")
      expect(lines[2].length).to be < 200
    end

    it "shows reminder times as numbers, with one in the singular" do
      result = described_class.call(server_context: mcp_modern_context(user), meeting_time_id: meeting_time.public_id,
                                    reminders: [ { time: 1.0, type: "hours", method: "notification" },
                                                 { time: "2.50", type: "days", method: "email" } ])
      message = result.input_requests.dig(McpTools::Confirmation::KEY, :params, :message)

      expect(message).to include("to 1 hour before by notification, 2.5 days before by email.")
    end

    it "does not take the same answer again after the change is undone" do
      state  = question.request_state
      answer = -> { confirmed_call(input_responses: mcp_confirmation("accept"), request_state: state) }

      expect(answer.call.structured_content).to include(result: :saved)
      travel(1.second) { call(color: "peacock", title_template: "Old {{title}}", reminders: []) }

      expect(answer.call).to be_a(MCP::Server::InputRequiredResult)
      expect(EventPreference.sole).to have_attributes(color_id: GoogleCalendar::Colors::PEACOCK, title_template: "Old {{title}}")
    end
  end
end

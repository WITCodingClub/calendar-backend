# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpTools::UpdateCalendarSettings do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

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

  describe "confirmation" do
    def message(level, **arguments)
      result = described_class.call(server_context: mcp_modern_context(user), level: level, **arguments)
      result.input_requests.dig(McpTools::Confirmation::KEY, :params, :message)
    end

    it "names the events that the level covers" do
      expect(message("all_classes", color: "sage")).to start_with("Change the calendar events of all your classes:\n")
      expect(message("lecture", color: "sage")).to start_with("Change the calendar events of every lecture class:")
      expect(message("final_exam", color: "sage")).to start_with("Change the calendar events of your final exams:")
      expect(message("university", color: "sage")).to start_with("Change the calendar events of all university calendar events:")
      expect(message("university:holiday", color: "sage")).to include("university calendar events in the holiday category")
      expect(CalendarPreference.count).to eq(0)
    end

    it "lists each field that changes and says that a class's own settings stay" do
      create(:calendar_preference, user: user, scope: :global, visibility: "public",
                                   reminder_settings: [ { "time" => "1", "type" => "hours", "method" => "popup" } ])

      lines = message("all_classes", visibility: "private", reminders: [ { time: 10, type: "minutes", method: "email" } ]).lines.map(&:chomp)

      expect(lines.drop(1)).to eq([
        "- Visibility: from public to private.",
        "- Reminders: from 1 hour before by notification to 10 minutes before by email.",
        "A kind of class (such as lecture) or a class with settings of its own keeps them."
      ])
    end

    it "leaves out a reminder stored as popup that the call sends as notification" do
      create(:calendar_preference, user: user, scope: :global, reminder_settings: [ { "time" => "10", "type" => "minutes", "method" => "popup" } ])

      lines = message("all_classes", color: "sage", reminders: [ { time: 10, type: "minutes", method: "notification" } ]).lines.map(&:chomp)

      expect(lines.drop(1)).to eq([ "- Color: from not set to Sage.", "A kind of class (such as lecture) or a class with settings of its own keeps them." ])
    end

    it "saves on accept and keeps the settings on decline" do
      question = described_class.call(server_context: mcp_modern_context(user), level: "lecture", color: "sage")
      retry_call = lambda do |action|
        context = mcp_modern_context(user, input_responses: mcp_confirmation(action), request_state: question.request_state)
        described_class.call(server_context: context, level: "lecture", color: "sage").structured_content
      end

      expect(retry_call.call("decline")).to include(result: :unchanged, settings: nil, not_changed: include(reason: "declined"))
      expect(CalendarPreference.count).to eq(0)

      expect(retry_call.call("accept")).to include(result: :saved, settings: include(color_id: GoogleCalendar::Colors::SAGE))
    end

    it "ends with what keeps its own settings at each level" do
      expect(message("laboratory", color: "sage").lines.last).to eq("A class with settings of its own keeps them.")
      expect(message("university", color: "sage").lines.last).to eq("A university event category with settings of its own keeps them.")
      expect(message("final_exam", color: "sage").lines.last).to start_with("- Color:")
      expect(message("university:holiday", color: "sage").lines.last).to start_with("- Color:")
    end

    describe "the university color" do
      let!(:university) { create(:calendar_preference, :uni_cal_global, user: user, color_id: GoogleCalendar::Colors::SAGE) }

      before do
        # The create above ends category colors, so add them after it.
        create(:calendar_preference, :uni_cal_category, user: user, event_type: "holiday", color_id: "#d50000")
        create(:calendar_preference, :uni_cal_category, user: user, event_type: "registration", color_id: "#0b8043")
      end

      def category_colors = CalendarPreference.where(scope: :uni_cal_category).where.not(color_id: nil).count

      it "says that a new color removes the category colors" do
        lines = message("university", color: "tomato").lines.map(&:chomp)

        expect(lines.drop(1)).to eq([
          "- Color: from Sage to Tomato.",
          "- Removes the colors of 2 university event categories, so the new color shows on all university events.",
          "Each category keeps its other settings."
        ])
        expect(category_colors).to eq(2)
      end

      it "asks before the same color again removes the category colors" do
        expect(message("university", color: "sage")).to include("Removes the colors of 2 university event categories")
      end

      it "keeps the category colors for a change that does not set the color" do
        result = call(level: "university", visibility: "private")

        expect(result.structured_content).to include(result: :saved)
        expect(category_colors).to eq(2)
      end
    end

    it "refuses a change that cannot be saved before it asks" do
      result = described_class.call(server_context: mcp_modern_context(user), level: "all_classes", title_template: "{{secret}}")

      expect(result).to be_a(MCP::Tool::Response)
      expect(result.error?).to be(true)
      expect(result.content.first[:text]).to include("Disallowed variables: secret")
    end

    it "does not take the same answer again after the change" do
      create(:calendar_preference, user: user, scope: :global, color_id: GoogleCalendar::Colors::TOMATO)
      question = described_class.call(server_context: mcp_modern_context(user), level: "all_classes", color: "sage")
      answer = lambda do
        context = mcp_modern_context(user, input_responses: mcp_confirmation("accept"), request_state: question.request_state)
        described_class.call(server_context: context, level: "all_classes", color: "sage")
      end

      expect(answer.call.structured_content).to include(result: :saved)
      travel(1.second) { call(level: "all_classes", color: "tomato") }

      expect(answer.call).to be_a(MCP::Server::InputRequiredResult)
      expect(CalendarPreference.sole.color_id).to eq(GoogleCalendar::Colors::TOMATO)
    end
  end
end

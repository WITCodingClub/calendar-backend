# frozen_string_literal: true

require "rails_helper"

RSpec.describe PreferenceResolver, "for Brightspace deadlines" do
  let(:user) { create(:user) }
  let(:offering) { create(:brightspace_course_offering, connection: create(:brightspace_connection, user: user)) }
  let(:assignment) { create(:brightspace_assignment, course_offering: offering) }

  before { allow(GoogleCalendarSyncJob).to receive(:perform_later) }

  def resolve = described_class.new(user).resolve_with_sources(assignment)

  it "uses the deadline defaults, not the course defaults" do
    create(:calendar_preference, user: user, scope: :global, title_template: "{{faculty}}: {{title}}")

    result = resolve

    expect(result[:preferences]).to include(title_template: "{{title}}", color_id: GoogleColors::BANANA,
                                            reminder_settings: [ { "time" => "1", "type" => "days", "method" => "popup" } ])
    expect(result[:sources][:title_template]).to eq("system_default")
  end

  it "takes the class preference before the event type preference" do
    create(:calendar_preference, user: user, scope: :event_type, event_type: "brightspace_assignment",
                                 title_template: "Due: {{title}}", color_id: "#0b8043")
    create(:brightspace_class_preference, course_offering: offering, title_template: "{{class_title}}: {{title}}")

    result = resolve

    expect(result[:preferences]).to include(title_template: "{{class_title}}: {{title}}", color_id: "#0b8043")
    expect(result[:sources]).to include(title_template: "brightspace_class", color_id: "event_type:brightspace_assignment")
  end

  it "turns reminders off for finished work" do
    create(:brightspace_class_preference, course_offering: offering,
                                          reminder_settings: [ { "time" => "2", "type" => "hours", "method" => "popup" } ])
    assignment.update!(submission_status: "submitted")

    expect(resolve[:preferences][:reminder_settings]).to eq([])
    expect(resolve[:sources][:reminder_settings]).to eq("finished")
  end

  it "runs no class preference query for course events" do
    meeting_time = create(:course_meeting_time)
    resolver = described_class.new(user)

    queries = []
    callback = ->(*, payload) { queries << payload[:sql] }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { resolver.resolve_for(meeting_time) }

    expect(queries.grep(/brightspace_class_preferences/)).to be_empty
  end
end

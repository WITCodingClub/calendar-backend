# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpTools::PreviewTemplate do
  let(:user) { create(:user) }
  let(:course) { create(:course, subject: "COMP", course_number: 1050, title: "Computer Science II") }
  let(:meeting_time) { create(:course_meeting_time, course: course) }

  before { create(:enrollment, user: user, course: course) }

  def call(**arguments) = described_class.call(server_context: mcp_context(user), **arguments)

  it "renders the template for the class without saving anything" do
    result = call(template: "Class: {{title}}", meeting_time_id: meeting_time.public_id)

    expect(result.structured_content).to eq(template: "Class: {{title}}", rendered: "Class: Computer Science II")
    expect(EventPreference.count).to eq(0)
  end

  it "explains a template that is not valid" do
    result = call(template: "{{password}}", meeting_time_id: meeting_time.public_id)

    expect(result.error?).to be(true)
    expect(result.content.first[:text]).to include("not valid", "password")
  end

  it "does not find a class the user does not take" do
    result = call(template: "{{title}}", meeting_time_id: create(:course_meeting_time).public_id)

    expect(result.error?).to be(true)
  end
end

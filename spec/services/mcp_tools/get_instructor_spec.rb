# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpTools::GetInstructor do
  let(:user) { create(:user) }

  def call(id) = described_class.call(server_context: { user: user }, instructor_id: id)

  it "gets an instructor by public id" do
    faculty = create(:faculty)

    expect(call(faculty.public_id).structured_content).to include(pub_id: faculty.public_id)
  end

  it "returns a tool error for an unknown id" do
    expect(call("fac_nope").content.first[:text]).to include("No instructor fac_nope")
  end
end

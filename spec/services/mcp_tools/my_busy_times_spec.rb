# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpTools::MyBusyTimes do
  let(:user) { create(:user) }

  def call(**arguments) = described_class.call(server_context: { user: user }, **arguments)

  it "lists the busy blocks of the user" do
    exam = create(:final_exam, exam_date: Date.new(2026, 12, 17), course: create(:course))
    create(:enrollment, user: user, course: exam.course)

    result = call(start_date: "2026-12-17", end_date: "2026-12-17")

    expect(result.structured_content[:busy]).to eq([ { date: "2026-12-17", weekday: "thursday", start: "08:00", end: "10:00" } ])
  end

  it "refuses an end date before the start date" do
    expect(call(start_date: "2026-12-17", end_date: "2026-12-01").content.first[:text]).to include("must not be before")
  end

  it "refuses a range longer than BusyBlocks allows" do
    result = call(start_date: "2026-01-01", end_date: "2026-12-31")

    expect(result.content.first[:text]).to include("#{BusyBlocks::MAX_DAYS} days or fewer")
  end
end

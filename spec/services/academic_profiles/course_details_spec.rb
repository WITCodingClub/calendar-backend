# frozen_string_literal: true

require "rails_helper"

RSpec.describe AcademicProfiles::CourseDetails do
  def queries(&)
    count = 0
    ActiveSupport::Notifications.subscribed(->(*) { count += 1 }, "sql.active_record", &)
    count
  end

  it "gives the details of a code from its own row, or from the row of an alias" do
    create(:catalog_course, :with_details, subject_code: "WDGT", course_number: 1000, title: "Widget Basics",
                                           description: "Making widgets.", typically_offered: %w[Fall])
    details = described_class.new([ [ "WDGT", 1000 ], [ "WDGT", 100 ], [ "WDGT", 9999 ] ], { [ "WDGT", 100 ] => [ [ "WDGT", 1000 ] ] })

    expected = { title: "Widget Basics", description: "Making widgets.", credit_hours: 4, typically_offered: %w[Fall] }
    expect(details.for([ "WDGT", 1000 ])).to eq(expected)
    expect(details.for([ "WDGT", 100 ])).to eq(expected)
    expect(details.for([ "WDGT", 9999 ])).to eq(described_class::UNKNOWN)
  end

  it "loads every code in one query, and none for no code" do
    create(:catalog_course, subject_code: "WDGT", course_number: 1000)
    create(:catalog_course, subject_code: "GEAR", course_number: 2000)
    details = described_class.new([ [ "WDGT", 1000 ], [ "GEAR", 2000 ] ])

    expect(queries { details.for([ "WDGT", 1000 ]) && details.for([ "GEAR", 2000 ]) }).to eq(1)
    expect(queries { described_class.new([]).for([ "WDGT", 1000 ]) }).to eq(0)
  end
end

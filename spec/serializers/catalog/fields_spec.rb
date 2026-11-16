# frozen_string_literal: true

require "rails_helper"

RSpec.describe Catalog::Fields do
  it "counts the minutes of a meeting across the hour" do
    meeting_time = build(:course_meeting_time, begin_time: 945, end_time: 1100)

    expect(described_class.duration_minutes(meeting_time)).to eq(75)
  end

  it "splits the tags of a review" do
    expect(described_class.review_tags(build(:rmp_rating, rating_tags: "Tough grader-- Caring --"))).to eq([ "Tough grader", "Caring" ])
  end

  it "gives no ratings for the Rate My Professors no-data numbers" do
    faculty = create(:faculty)
    create(:rating_distribution, faculty: faculty, num_ratings: 4, would_take_again_percent: -1)

    expect(described_class.rmp(faculty.reload)).to include(num_ratings: 4, would_take_again_percent: nil)
    expect(described_class.rmp(create(:faculty))).to be_nil
  end
end

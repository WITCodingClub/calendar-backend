# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/seeds/people")

RSpec.describe Seeds::People do
  it "enrolls students and an admin in active courses of the latest term" do
    create(:course, term: create(:term, uid: 202610, year: 2025, season: :fall))
    term = create(:term, uid: 202710, year: 2026, season: :fall)
    courses = create_list(:course, 6, term: term)
    create(:course, term: term, status: :cancelled)

    people = described_class.call(count: 4, courses_per_student: 1..3)
    enrolled_course_ids = Enrollment.where(user: people).pluck(:course_id)

    expect(people.size).to eq(5)
    expect(User.find_by!(email: described_class::ADMIN_EMAIL).access_level).to eq("admin")
    expect(enrolled_course_ids).not_to be_empty
    expect(courses.map(&:id)).to include(*enrolled_course_ids)
    expect(Friendship.accepted.count).to eq(2)
  end

  it "creates nobody when there are no courses" do
    expect(described_class.call(count: 2)).to eq([])
    expect(User.count).to eq(0)
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe Courses::FinalExamsQuery do
  let(:user) { create(:user) }
  let(:term) { create(:term) }

  def enrolled_exam(term:, user:, **attributes)
    course = create(:course, term: term)
    create(:enrollment, user: user, course: course)
    create(:final_exam, term: term, crn: course.crn, course: course, **attributes)
  end

  it "returns the user's finals in the term, in date and time order" do
    later   = enrolled_exam(term: term, user: user, exam_date: Date.new(2026, 12, 18))
    earlier = enrolled_exam(term: term, user: user, exam_date: Date.new(2026, 12, 17), start_time: 1300, end_time: 1500)
    first   = enrolled_exam(term: term, user: user, exam_date: Date.new(2026, 12, 17), start_time: 800, end_time: 1000)
    enrolled_exam(term: create(:term), user: user)
    enrolled_exam(term: term, user: create(:user))

    expect(described_class.new(user, term).call.to_a).to eq([ first, earlier, later ])
  end
end

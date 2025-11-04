# frozen_string_literal: true

# == Schema Information
#
# Table name: courses
# Database name: primary
#
#  id             :bigint           not null, primary key
#  course_number  :integer
#  credit_hours   :integer
#  crn            :integer
#  end_date       :date
#  grade_mode     :string
#  schedule_type  :string           not null
#  section_number :string           not null
#  start_date     :date
#  subject        :string
#  title          :string
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  term_id        :bigint           not null
#
# Indexes
#
#  index_courses_on_crn      (crn) UNIQUE
#  index_courses_on_term_id  (term_id)
#
# Foreign Keys
#
#  fk_rails_...  (term_id => terms.id)
#
require "rails_helper"

RSpec.describe Course do
  describe "calendar sync tracking" do
    let(:term) { create(:term) }
    let(:course) { create(:course, term: term) }
    let(:user) { create(:user, google_course_calendar_id: "cal_123", calendar_needs_sync: false) }

    before do
      create(:enrollment, user: user, course: course, term: term)
      user.update_column(:calendar_needs_sync, false)
    end

    context "when course title changes" do
      it "marks enrolled users as needing sync" do
        expect {
          course.update!(title: "New Course Title")
        }.to change { user.reload.calendar_needs_sync }.from(false).to(true)
      end
    end

    context "when course start_date changes" do
      it "marks enrolled users as needing sync" do
        expect {
          course.update!(start_date: Time.zone.today + 1.week)
        }.to change { user.reload.calendar_needs_sync }.from(false).to(true)
      end
    end

    context "when irrelevant field changes" do
      it "does not mark enrolled users as needing sync" do
        expect {
          course.update!(credit_hours: 4)
        }.not_to(change { user.reload.calendar_needs_sync })
      end
    end

    context "when course is destroyed" do
      it "marks enrolled users as needing sync" do
        expect {
          course.destroy
        }.to change { user.reload.calendar_needs_sync }.from(false).to(true)
      end
    end
  end
end

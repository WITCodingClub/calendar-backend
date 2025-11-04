# frozen_string_literal: true

# == Schema Information
#
# Table name: enrollments
# Database name: primary
#
#  id         :bigint           not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  course_id  :bigint           not null
#  term_id    :bigint           not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_enrollments_on_course_id        (course_id)
#  index_enrollments_on_term_id          (term_id)
#  index_enrollments_on_user_class_term  (user_id,course_id,term_id) UNIQUE
#  index_enrollments_on_user_id          (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (course_id => courses.id)
#  fk_rails_...  (term_id => terms.id)
#  fk_rails_...  (user_id => users.id)
#
require "rails_helper"

RSpec.describe Enrollment do
  describe "calendar sync tracking" do
    let(:user) { create(:user, google_course_calendar_id: "cal_123", calendar_needs_sync: false) }
    let(:term) { create(:term) }
    let(:course) { create(:course, term: term) }

    context "when enrollment is created" do
      it "marks user calendar as needing sync" do
        expect {
          create(:enrollment, user: user, course: course, term: term)
        }.to change { user.reload.calendar_needs_sync }.from(false).to(true)
      end

      it "does not mark user without google calendar" do
        user_without_cal = create(:user, google_course_calendar_id: nil)

        expect {
          create(:enrollment, user: user_without_cal, course: course, term: term)
        }.not_to(change { user_without_cal.reload.calendar_needs_sync })
      end
    end

    context "when enrollment is destroyed" do
      let!(:enrollment) { create(:enrollment, user: user, course: course, term: term) }

      before do
        user.update_column(:calendar_needs_sync, false)
      end

      it "marks user calendar as needing sync" do
        expect {
          enrollment.destroy
        }.to change { user.reload.calendar_needs_sync }.from(false).to(true)
      end
    end
  end
end

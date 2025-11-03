# == Schema Information
#
# Table name: meeting_times
# Database name: primary
#
#  id                    :bigint           not null, primary key
#  begin_time            :integer          not null
#  day_of_week           :integer
#  end_date              :datetime         not null
#  end_time              :integer          not null
#  hours_week            :integer
#  meeting_schedule_type :integer
#  meeting_type          :integer
#  start_date            :datetime         not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  course_id             :bigint           not null
#  room_id               :bigint           not null
#
# Indexes
#
#  index_meeting_times_on_course_id    (course_id)
#  index_meeting_times_on_day_of_week  (day_of_week)
#  index_meeting_times_on_room_id      (room_id)
#
# Foreign Keys
#
#  fk_rails_...  (course_id => courses.id)
#  fk_rails_...  (room_id => rooms.id)
#
require 'rails_helper'

RSpec.describe MeetingTime, type: :model do
  describe 'calendar sync tracking' do
    let(:term) { create(:term) }
    let(:course) { create(:course, term: term) }
    let(:room) { create(:room) }
    let(:meeting_time) { create(:meeting_time, course: course, room: room) }
    let(:user) { create(:user, google_course_calendar_id: 'cal_123', calendar_needs_sync: false) }
    
    before do
      create(:enrollment, user: user, course: course, term: term)
      user.update_column(:calendar_needs_sync, false)
    end

    context 'when meeting time changes' do
      it 'marks enrolled users as needing sync' do
        expect {
          meeting_time.update!(begin_time: 1000)
        }.to change { user.reload.calendar_needs_sync }.from(false).to(true)
      end
    end

    context 'when day_of_week changes' do
      it 'marks enrolled users as needing sync' do
        expect {
          meeting_time.update!(day_of_week: :tuesday)
        }.to change { user.reload.calendar_needs_sync }.from(false).to(true)
      end
    end

    context 'when meeting_time is destroyed' do
      it 'marks enrolled users as needing sync' do
        expect {
          meeting_time.destroy
        }.to change { user.reload.calendar_needs_sync }.from(false).to(true)
      end
    end
  end
end

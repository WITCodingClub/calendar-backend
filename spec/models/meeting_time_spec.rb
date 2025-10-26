# == Schema Information
#
# Table name: meeting_times
#
#  id                    :bigint           not null, primary key
#  begin_time            :integer          not null
#  end_date              :datetime         not null
#  end_time              :integer          not null
#  friday                :boolean
#  hours_week            :integer
#  meeting_schedule_type :integer
#  meeting_type          :integer
#  monday                :boolean
#  saturday              :boolean
#  start_date            :datetime         not null
#  sunday                :boolean
#  thursday              :boolean
#  tuesday               :boolean
#  wednesday             :boolean
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  academic_class_id     :bigint           not null
#  room_id               :bigint           not null
#
# Indexes
#
#  index_meeting_times_on_academic_class_id  (academic_class_id)
#  index_meeting_times_on_room_id            (room_id)
#
# Foreign Keys
#
#  fk_rails_...  (academic_class_id => academic_classes.id)
#  fk_rails_...  (room_id => rooms.id)
#
require 'rails_helper'

RSpec.describe MeetingTime, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end

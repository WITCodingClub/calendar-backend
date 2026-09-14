# frozen_string_literal: true

# == Schema Information
#
# Table name: rooms
#
#  id                  :bigint           not null, primary key
#  capacity            :integer
#  floor               :integer          not null
#  formal_name         :string
#  number              :string           not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  building_id         :bigint           not null
#  twenty_five_live_id :integer
#
# Indexes
#
#  index_rooms_on_building_id             (building_id)
#  index_rooms_on_building_id_and_number  (building_id,number) UNIQUE
#  index_rooms_on_twenty_five_live_id     (twenty_five_live_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (building_id => buildings.id)
#
require "rails_helper"

RSpec.describe Room, type: :model do
  it { is_expected.to belong_to(:building) }
  it { is_expected.to have_many(:meeting_time_rooms).class_name("Course::MeetingTimeRoom").dependent(:destroy) }
  it { is_expected.to have_many(:meeting_times).class_name("Course::MeetingTime").through(:meeting_time_rooms) }
end

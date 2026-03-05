# frozen_string_literal: true

# == Schema Information
#
# Table name: twenty_five_live_reservations
# Database name: primary
#
#  id                        :bigint           not null, primary key
#  event_end_dt              :datetime
#  event_start_dt            :datetime
#  expected_count            :integer
#  reservation_state         :integer
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  reservation_id            :integer          not null
#  twenty_five_live_event_id :bigint           not null
#
# Indexes
#
#  idx_on_twenty_five_live_event_id_27330189d9            (twenty_five_live_event_id)
#  index_twenty_five_live_reservations_on_reservation_id  (reservation_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (twenty_five_live_event_id => twenty_five_live_events.id)
#
FactoryBot.define do
  factory :"twenty_five_live/reservation", class: "TwentyFiveLive::Reservation" do
    event { association :"twenty_five_live/event" }
    sequence(:reservation_id) { |n| 50_000 + n }
    event_start_dt            { 1.day.from_now.beginning_of_day + 12.hours }
    event_end_dt              { 1.day.from_now.beginning_of_day + 14.hours }
    reservation_state         { 2 }
    expected_count            { nil }
  end
end

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
module TwentyFiveLive
  class Reservation < ApplicationRecord
    self.table_name = "twenty_five_live_reservations"

    belongs_to :event, class_name: "TwentyFiveLive::Event", foreign_key: :twenty_five_live_event_id, inverse_of: :reservations

    has_many :space_reservations, class_name: "TwentyFiveLive::SpaceReservation", foreign_key: :twenty_five_live_reservation_id, inverse_of: :reservation, dependent: :destroy
    has_many :spaces,             class_name: "TwentyFiveLive::Space",            through: :space_reservations

    validates :reservation_id, presence: true, uniqueness: true

    scope :upcoming, -> { where(event_start_dt: Time.current..) }

  end
end

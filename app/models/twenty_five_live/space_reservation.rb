# frozen_string_literal: true

# == Schema Information
#
# Table name: twenty_five_live_space_reservations
# Database name: primary
#
#  id                              :bigint           not null, primary key
#  layout_name                     :string
#  selected_layout_capacity        :integer
#  created_at                      :datetime         not null
#  updated_at                      :datetime         not null
#  layout_id                       :integer
#  twenty_five_live_reservation_id :bigint           not null
#  twenty_five_live_space_id       :bigint           not null
#
# Indexes
#
#  idx_on_twenty_five_live_reservation_id_36a801db84  (twenty_five_live_reservation_id)
#  idx_on_twenty_five_live_space_id_eb37f1572a        (twenty_five_live_space_id)
#
# Foreign Keys
#
#  fk_rails_...  (twenty_five_live_reservation_id => twenty_five_live_reservations.id)
#  fk_rails_...  (twenty_five_live_space_id => twenty_five_live_spaces.id)
#
module TwentyFiveLive
  class SpaceReservation < ApplicationRecord
    self.table_name = "twenty_five_live_space_reservations"

    belongs_to :reservation, class_name: "TwentyFiveLive::Reservation", foreign_key: :twenty_five_live_reservation_id, inverse_of: :space_reservations
    belongs_to :space,       class_name: "TwentyFiveLive::Space",       foreign_key: :twenty_five_live_space_id,       inverse_of: :space_reservations

  end
end

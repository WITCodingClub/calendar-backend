# frozen_string_literal: true

# == Schema Information
#
# Table name: twenty_five_live_spaces
# Database name: primary
#
#  id            :bigint           not null, primary key
#  building_name :string
#  formal_name   :string
#  max_capacity  :integer
#  space_name    :string
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  space_id      :integer          not null
#
# Indexes
#
#  index_twenty_five_live_spaces_on_space_id  (space_id) UNIQUE
#
FactoryBot.define do
  factory :"twenty_five_live/space", class: "TwentyFiveLive::Space" do
    sequence(:space_id) { |n| 10_000 + n }
    sequence(:space_name) { |n| "Room #{n}" }
    formal_name          { "#{space_name} (Formal)" }
    building_name        { "Main Building" }
    max_capacity         { 100 }
  end
end

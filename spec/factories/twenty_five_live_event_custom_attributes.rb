# frozen_string_literal: true

# twenty_five_live_id sequences start well above the highest id seeded in
# TwentyFiveLive::EventCustomAttribute::EVENT_CUSTOM_ATTRIBUTES.
# == Schema Information
#
# Table name: twenty_five_live_event_custom_attributes
#
#  id                  :bigint           not null, primary key
#  attribute_type      :string
#  attribute_type_name :string
#  defn_state          :integer          default(1), not null
#  multi_val           :string
#  name                :string           not null
#  sort_order          :integer
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  twenty_five_live_id :integer          not null
#
# Indexes
#
#  idx_on_twenty_five_live_id_bd51b01498  (twenty_five_live_id) UNIQUE
#
FactoryBot.define do
  factory :twenty_five_live_event_custom_attribute, class: "TwentyFiveLive::EventCustomAttribute" do
    sequence(:twenty_five_live_id) { |n| 900_000 + n }
    sequence(:name) { |n| "Factory Attribute #{n}" }
  end
end

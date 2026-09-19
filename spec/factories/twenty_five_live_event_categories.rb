# frozen_string_literal: true

# twenty_five_live_id sequences start well above TwentyFiveLive::EventCategory::EVENT_CATEGORIES'
# highest seeded id (124), so factory rows never collide with real category ids.
# == Schema Information
#
# Table name: twenty_five_live_event_categories
#
#  id                  :bigint           not null, primary key
#  defn_state          :integer          default(1), not null
#  name                :string           not null
#  sort_order          :integer
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  twenty_five_live_id :integer          not null
#
# Indexes
#
#  index_twenty_five_live_event_categories_on_twenty_five_live_id  (twenty_five_live_id) UNIQUE
#
FactoryBot.define do
  factory :twenty_five_live_event_category, class: "TwentyFiveLive::EventCategory" do
    sequence(:twenty_five_live_id) { |n| 900_000 + n }
    sequence(:name) { |n| "Factory Category #{n}" }
  end
end

# frozen_string_literal: true

# == Schema Information
#
# Table name: twenty_five_live_resources
#
#  id                  :bigint           not null, primary key
#  assign_perm         :string
#  name                :string           not null
#  schedule_perm       :string
#  stock_level         :integer
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  twenty_five_live_id :integer          not null
#
# Indexes
#
#  index_twenty_five_live_resources_on_twenty_five_live_id  (twenty_five_live_id) UNIQUE
#
FactoryBot.define do
  factory :twenty_five_live_resource, class: "TwentyFiveLive::Resource" do
    sequence(:twenty_five_live_id) { |n| 900_000 + n }
    sequence(:name) { |n| "Factory Resource #{n}" }
  end
end

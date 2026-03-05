# frozen_string_literal: true

# == Schema Information
#
# Table name: twenty_five_live_categories
# Database name: primary
#
#  id            :bigint           not null, primary key
#  category_name :string
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  category_id   :integer          not null
#
# Indexes
#
#  index_twenty_five_live_categories_on_category_id  (category_id) UNIQUE
#
FactoryBot.define do
  factory :"twenty_five_live/category", class: "TwentyFiveLive::Category" do
    sequence(:category_id)   { |n| 300 + n }
    sequence(:category_name) { |n| "Category #{n}" }
  end
end

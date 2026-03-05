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
module TwentyFiveLive
  class Category < ApplicationRecord
    self.table_name = "twenty_five_live_categories"

    has_many :event_categories, class_name: "TwentyFiveLive::EventCategory", dependent: :destroy
    has_many :events,           class_name: "TwentyFiveLive::Event",         through: :event_categories

    validates :category_id, presence: true, uniqueness: true

    def self.find_or_create_by_category_id(attrs)
      find_or_create_by(category_id: attrs[:category_id]) do |cat|
        cat.assign_attributes(attrs.except(:category_id))
      end
    end

  end
end

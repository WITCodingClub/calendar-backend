# frozen_string_literal: true

# == Schema Information
#
# Table name: catalog_years
#
#  id          :bigint           not null, primary key
#  base_url    :string
#  imported_at :datetime
#  source      :string           default("html"), not null
#  start_year  :integer          not null
#  status      :string           default("pending"), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
# Indexes
#
#  index_catalog_years_on_start_year  (start_year) UNIQUE
#
FactoryBot.define do
  factory :catalog_year do
    sequence(:start_year) { |n| 2012 + n }

    trait :imported do
      status { "imported" }
      imported_at { Time.current }
    end

    trait :from_pdf do
      source { "pdf" }
    end
  end
end

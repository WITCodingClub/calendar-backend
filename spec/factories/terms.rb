# frozen_string_literal: true

# == Schema Information
#
# Table name: terms
# Database name: primary
#
#  id                  :bigint           not null, primary key
#  catalog_imported    :boolean          default(FALSE), not null
#  catalog_imported_at :datetime
#  end_date            :date
#  season              :integer
#  start_date          :date
#  uid                 :integer          not null
#  year                :integer
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#
# Indexes
#
#  index_terms_on_uid              (uid) UNIQUE
#  index_terms_on_year_and_season  (year,season) UNIQUE
#
FactoryBot.define do
  factory :term do
    sequence(:uid) { |n| 202500 + n }
    sequence(:year) { |n| 2025 + (n / 3) }
    sequence(:season) { |n| [:spring, :summer, :fall][n % 3] }

    trait :current do
      start_date { 1.month.ago.to_date }
      end_date { 3.months.from_now.to_date }
    end

    trait :future do
      start_date { 4.months.from_now.to_date }
      end_date { 8.months.from_now.to_date }
    end

    trait :past do
      start_date { 8.months.ago.to_date }
      end_date { 4.months.ago.to_date }
    end
  end
end

# frozen_string_literal: true

# == Schema Information
#
# Table name: terms
# Database name: primary
#
#  id                  :bigint           not null, primary key
#  catalog_imported    :boolean          default(FALSE), not null
#  catalog_imported_at :datetime
#  season              :integer
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
  end
end

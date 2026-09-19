# frozen_string_literal: true

# Factory values use a "FCT"/"Factory" prefix that never collides with the
# real building names and abbreviations seeded in spec/fixtures/buildings.yml
# (WT, COMP), which leak into every test because they load outside the
# transaction.
# == Schema Information
#
# Table name: buildings
#
#  id                          :bigint           not null, primary key
#  abbreviation                :string           not null
#  formal_name                 :string
#  name                        :string           not null
#  twenty_five_live_checked_at :datetime
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  twenty_five_live_id         :integer
#
# Indexes
#
#  index_buildings_on_abbreviation         (abbreviation) UNIQUE
#  index_buildings_on_name                 (name) UNIQUE
#  index_buildings_on_twenty_five_live_id  (twenty_five_live_id) UNIQUE
#
FactoryBot.define do
  factory :building do
    sequence(:abbreviation) { |n| "FCT#{n}" }
    sequence(:name) { |n| "Factory Building #{n}" }
  end
end

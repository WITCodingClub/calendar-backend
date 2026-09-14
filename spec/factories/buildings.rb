# frozen_string_literal: true

# Factory values use a "FCT"/"Factory" prefix that never collides with the
# real building names and abbreviations seeded in spec/fixtures/buildings.yml
# (WT, COMP), which leak into every test because they load outside the
# transaction.
FactoryBot.define do
  factory :building do
    sequence(:abbreviation) { |n| "FCT#{n}" }
    sequence(:name) { |n| "Factory Building #{n}" }
  end
end

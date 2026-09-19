# frozen_string_literal: true

# == Schema Information
#
# Table name: twenty_five_live_organizations
#
#  id                     :bigint           not null, primary key
#  code                   :string
#  name                   :string           not null
#  organization_type_name :string
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  twenty_five_live_id    :integer          not null
#
# Indexes
#
#  index_twenty_five_live_organizations_on_twenty_five_live_id  (twenty_five_live_id) UNIQUE
#
FactoryBot.define do
  factory :twenty_five_live_organization, class: "TwentyFiveLive::Organization" do
    sequence(:twenty_five_live_id) { |n| 900_000 + n }
    sequence(:name) { |n| "Factory Organization #{n}" }
  end
end

# frozen_string_literal: true

# == Schema Information
#
# Table name: twenty_five_live_organizations
# Database name: primary
#
#  id                     :bigint           not null, primary key
#  organization_name      :string
#  organization_title     :string
#  organization_type_name :string
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  organization_id        :integer          not null
#  organization_type_id   :integer
#
# Indexes
#
#  index_twenty_five_live_organizations_on_organization_id  (organization_id) UNIQUE
#
FactoryBot.define do
  factory :"twenty_five_live/organization", class: "TwentyFiveLive::Organization" do
    sequence(:organization_id)   { |n| 200 + n }
    sequence(:organization_name) { |n| "Organization #{n}" }
    organization_title           { nil }
    organization_type_id         { nil }
    organization_type_name       { nil }
  end
end

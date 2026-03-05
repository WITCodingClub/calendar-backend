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
module TwentyFiveLive
  class Organization < ApplicationRecord
    self.table_name = "twenty_five_live_organizations"

    has_many :event_organizations, class_name: "TwentyFiveLive::EventOrganization", dependent: :destroy
    has_many :events,              class_name: "TwentyFiveLive::Event",             through: :event_organizations

    validates :organization_id, presence: true, uniqueness: true

    def self.find_or_create_by_organization_id(attrs)
      find_or_create_by(organization_id: attrs[:organization_id]) do |org|
        org.assign_attributes(attrs.except(:organization_id))
      end
    end

  end
end

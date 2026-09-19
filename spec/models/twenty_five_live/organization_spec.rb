# frozen_string_literal: true

require "rails_helper"

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
RSpec.describe TwentyFiveLive::Organization, type: :model do
  subject { create(:twenty_five_live_organization) }

  it { is_expected.to validate_presence_of(:twenty_five_live_id) }
  it { is_expected.to validate_uniqueness_of(:twenty_five_live_id) }
  it { is_expected.to validate_presence_of(:name) }
end

# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: twenty_five_live_resources
#
#  id                  :bigint           not null, primary key
#  assign_perm         :string
#  name                :string           not null
#  schedule_perm       :string
#  stock_level         :integer
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  twenty_five_live_id :integer          not null
#
# Indexes
#
#  index_twenty_five_live_resources_on_twenty_five_live_id  (twenty_five_live_id) UNIQUE
#
RSpec.describe TwentyFiveLive::Resource, type: :model do
  subject { create(:twenty_five_live_resource) }

  it { is_expected.to validate_presence_of(:twenty_five_live_id) }
  it { is_expected.to validate_uniqueness_of(:twenty_five_live_id) }
  it { is_expected.to validate_presence_of(:name) }
end

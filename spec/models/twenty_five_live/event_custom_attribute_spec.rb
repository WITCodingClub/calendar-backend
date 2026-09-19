# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: twenty_five_live_event_custom_attributes
#
#  id                  :bigint           not null, primary key
#  attribute_type      :string
#  attribute_type_name :string
#  defn_state          :integer          default(1), not null
#  multi_val           :string
#  name                :string           not null
#  sort_order          :integer
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  twenty_five_live_id :integer          not null
#
# Indexes
#
#  idx_on_twenty_five_live_id_bd51b01498  (twenty_five_live_id) UNIQUE
#
RSpec.describe TwentyFiveLive::EventCustomAttribute, type: :model do
  subject { create(:twenty_five_live_event_custom_attribute) }

  it { is_expected.to validate_presence_of(:twenty_five_live_id) }
  it { is_expected.to validate_uniqueness_of(:twenty_five_live_id) }
  it { is_expected.to validate_presence_of(:name) }
end

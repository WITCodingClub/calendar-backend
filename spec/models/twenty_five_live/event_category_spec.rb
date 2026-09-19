# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: twenty_five_live_event_categories
#
#  id                  :bigint           not null, primary key
#  defn_state          :integer          default(1), not null
#  name                :string           not null
#  sort_order          :integer
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  twenty_five_live_id :integer          not null
#
# Indexes
#
#  index_twenty_five_live_event_categories_on_twenty_five_live_id  (twenty_five_live_id) UNIQUE
#
RSpec.describe TwentyFiveLive::EventCategory, type: :model do
  subject { create(:twenty_five_live_event_category) }

  it { is_expected.to validate_presence_of(:twenty_five_live_id) }
  it { is_expected.to validate_uniqueness_of(:twenty_five_live_id) }
  it { is_expected.to validate_presence_of(:name) }
end

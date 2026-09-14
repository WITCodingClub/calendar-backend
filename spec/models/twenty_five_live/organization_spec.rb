# frozen_string_literal: true

require "rails_helper"

RSpec.describe TwentyFiveLive::Organization, type: :model do
  subject { create(:twenty_five_live_organization) }

  it { is_expected.to validate_presence_of(:twenty_five_live_id) }
  it { is_expected.to validate_uniqueness_of(:twenty_five_live_id) }
  it { is_expected.to validate_presence_of(:name) }
end

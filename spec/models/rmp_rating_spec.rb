# frozen_string_literal: true

require "rails_helper"

RSpec.describe RmpRating, type: :model do
  subject { create(:rmp_rating) }

  it { is_expected.to belong_to(:faculty) }
  it { is_expected.to validate_presence_of(:rmp_id) }
  it { is_expected.to validate_uniqueness_of(:rmp_id) }
end

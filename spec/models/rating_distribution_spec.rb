# frozen_string_literal: true

require "rails_helper"

RSpec.describe RatingDistribution, type: :model do
  subject { create(:rating_distribution) }

  it { is_expected.to belong_to(:faculty) }
  it { is_expected.to validate_uniqueness_of(:faculty_id) }
end

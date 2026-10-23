# frozen_string_literal: true

require "rails_helper"

RSpec.describe AcademicProfile, type: :model do
  it { is_expected.to belong_to(:user) }

  # No matcher covers a unique index with no validation.
  it "allows one profile for each user" do
    profile = create(:academic_profile)

    expect { create(:academic_profile, user: profile.user) }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end

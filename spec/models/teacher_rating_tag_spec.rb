# frozen_string_literal: true

require "rails_helper"

RSpec.describe TeacherRatingTag, type: :model do
  subject { create(:teacher_rating_tag) }

  it { is_expected.to belong_to(:faculty) }

  it { is_expected.to validate_presence_of(:rmp_legacy_id) }
  it { is_expected.to validate_uniqueness_of(:rmp_legacy_id).scoped_to(:faculty_id) }
  it { is_expected.to validate_presence_of(:tag_name) }
  it { is_expected.to validate_numericality_of(:tag_count).is_greater_than_or_equal_to(0) }
end

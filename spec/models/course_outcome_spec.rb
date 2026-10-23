# frozen_string_literal: true

require "rails_helper"

RSpec.describe CourseOutcome, type: :model do
  subject { create(:course_outcome) }

  it { is_expected.to belong_to(:user) }
  it { is_expected.to belong_to(:course) }
  it { is_expected.to validate_uniqueness_of(:course_id).scoped_to(:user_id) }

  it do
    expect(subject).to define_enum_for(:outcome).with_values(described_class::OUTCOMES)
                                                .backed_by_column_of_type(:string).validating
  end

  it "counts both pass values as passed" do
    expect(described_class::OUTCOMES.keys.select { |value| build(:course_outcome, outcome: value).passed? })
      .to eq(%i[c_or_better passed_below_c])
  end
end

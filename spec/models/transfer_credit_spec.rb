# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: transfer_credits
#
#  id         :bigint           not null, primary key
#  code       :string           not null
#  credits    :integer
#  kind       :string
#  source     :string           not null
#  title      :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_transfer_credits_on_user_id_and_code  (user_id,code) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
RSpec.describe TransferCredit, type: :model do
  subject { create(:transfer_credit) }

  it { is_expected.to belong_to(:user) }
  it { is_expected.to validate_presence_of(:code) }
  it { is_expected.to validate_uniqueness_of(:code).scoped_to(:user_id).ignoring_case_sensitivity }
  it { is_expected.to validate_length_of(:title).is_at_most(described_class::MAX_TITLE_LENGTH) }
  it { is_expected.to validate_numericality_of(:credits).only_integer.is_in(0..described_class::MAX_CREDITS).allow_nil }

  it do
    expect(subject).to define_enum_for(:source).with_values(described_class::SOURCES)
                                               .backed_by_column_of_type(:string).validating
  end

  it do
    expect(subject).to define_enum_for(:kind).with_values(described_class::KINDS).with_prefix
                                             .backed_by_column_of_type(:string).validating(allowing_nil: true)
  end

  # normalizes runs before the custom format check, so no matcher covers the
  # pair of them.
  it "stores a course code as subject, space, number, and refuses text that is not a course code" do
    expect(build(:transfer_credit, code: "engl-1100").code).to eq("ENGL 1100")
    expect(build(:transfer_credit, code: "ENGL1100").key).to eq([ "ENGL", 1100 ])

    credit = build(:transfer_credit, code: "HUMN 1XXX")

    expect(credit).not_to be_valid
    expect(credit.errors[:code]).to include(a_string_including("course code"))
  end
end

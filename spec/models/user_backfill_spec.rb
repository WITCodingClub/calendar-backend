# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: user_backfills
#
#  id           :bigint           not null, primary key
#  completed_at :datetime         not null
#  name         :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  user_id      :bigint           not null
#
# Indexes
#
#  index_user_backfills_on_user_id_and_name  (user_id,name) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
RSpec.describe UserBackfill, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  subject { create(:user_backfill) }

  it { is_expected.to belong_to(:user) }
  it { is_expected.to validate_presence_of(:completed_at) }
  it { is_expected.to validate_uniqueness_of(:name).scoped_to(:user_id).ignoring_case_sensitivity }

  it do
    expect(subject).to define_enum_for(:name).with_values(described_class::NAMES)
                                             .backed_by_column_of_type(:string).validating
  end

  describe ".complete!" do
    let(:user) { create(:user) }

    it "creates the row" do
      freeze_time do
        described_class.complete!(user, "past_terms")

        expect(user.user_backfills.sole).to have_attributes(name: "past_terms", completed_at: Time.current)
      end
    end

    it "moves completed_at to now when the run is marked done again" do
      row = create(:user_backfill, user: user, completed_at: 1.day.ago)

      freeze_time do
        described_class.complete!(user, "past_terms")

        expect(row.reload.completed_at).to eq(Time.current)
      end
      expect(user.user_backfills.count).to eq(1)
    end
  end
end

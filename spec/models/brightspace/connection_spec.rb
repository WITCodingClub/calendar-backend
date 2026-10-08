# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: brightspace_connections
#
#  id                    :bigint           not null, primary key
#  connected_at          :datetime         not null
#  disconnected_at       :datetime
#  host                  :string           not null
#  last_synced_at        :datetime
#  reconnect_required_at :datetime
#  status                :string           default("active"), not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  learner_id            :string           not null
#  user_id               :bigint           not null
#
# Indexes
#
#  index_brightspace_connections_on_identity          (user_id,host,learner_id) UNIQUE
#  index_brightspace_connections_on_user_id           (user_id)
#  index_brightspace_connections_one_active_per_user  (user_id) UNIQUE WHERE ((status)::text = 'active'::text)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
RSpec.describe Brightspace::Connection, type: :model do
  subject { create(:brightspace_connection) }

  it { is_expected.to belong_to(:user) }
  it { is_expected.to have_many(:syncs).dependent(:destroy) }
  it { is_expected.to have_many(:course_offerings).dependent(:destroy) }

  it { is_expected.to validate_presence_of(:host) }
  it { is_expected.to validate_length_of(:host).is_at_most(255) }
  it { is_expected.to validate_presence_of(:learner_id) }
  it { is_expected.to validate_length_of(:learner_id).is_at_most(64) }
  it { is_expected.to validate_uniqueness_of(:learner_id).scoped_to(:user_id, :host).ignoring_case_sensitivity }
  it { is_expected.to validate_inclusion_of(:status).in_array(described_class::STATUSES) }
  it { is_expected.to validate_presence_of(:connected_at) }
  it { is_expected.to normalize(:host).from(" https://Brightspace.Example.edu/ ").to("brightspace.example.edu") }
  it { is_expected.not_to allow_values("not a host", "localhost", "a/b.edu").for(:host) }

  describe ".link!" do
    let(:user) { create(:user) }

    it "creates an active connection" do
      connection = described_class.link!(user: user, host: "brightspace.example.edu", learner_id: "123")

      expect(connection).to be_active
      expect(connection.user).to eq(user)
    end

    it "reuses the same account and keeps its data" do
      old = described_class.link!(user: user, host: "brightspace.example.edu", learner_id: "123")
      offering = create(:brightspace_course_offering, connection: old)
      old.disconnect!

      again = described_class.link!(user: user, host: "BRIGHTSPACE.example.edu", learner_id: "123")

      expect(again).to eq(old)
      expect(again).to be_active
      expect(again.course_offerings).to contain_exactly(offering)
    end

    it "deactivates the old account when another account links" do
      old = described_class.link!(user: user, host: "brightspace.example.edu", learner_id: "123")
      other = described_class.link!(user: user, host: "brightspace.example.edu", learner_id: "456")

      expect(old.reload).to be_disconnected
      expect(other).to be_active
      expect(user.brightspace_connections.active).to contain_exactly(other)
    end
  end

  describe ".current_for" do
    let(:user) { create(:user) }

    it "prefers the active connection" do
      create(:brightspace_connection, :disconnected, user: user, connected_at: 1.minute.ago)
      active = create(:brightspace_connection, user: user, connected_at: 1.day.ago)

      expect(described_class.current_for(user)).to eq(active)
    end

    it "falls back to the last connected account" do
      create(:brightspace_connection, :disconnected, user: user, connected_at: 2.days.ago)
      last = create(:brightspace_connection, :disconnected, user: user, connected_at: 1.day.ago)

      expect(described_class.current_for(user)).to eq(last)
    end

    it "is nil without a connection" do
      expect(described_class.current_for(user)).to be_nil
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: brightspace_deadline_changes
#
#  id            :bigint           not null, primary key
#  current_at    :datetime
#  detected_at   :datetime         not null
#  field         :string           not null
#  notified_at   :datetime
#  previous_at   :datetime
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  assignment_id :bigint           not null
#
# Indexes
#
#  index_brightspace_deadline_changes_on_assignment_id  (assignment_id)
#  index_brightspace_deadline_changes_unnotified        (notified_at) WHERE (notified_at IS NULL)
#
# Foreign Keys
#
#  fk_rails_...  (assignment_id => brightspace_assignments.id)
#
RSpec.describe Brightspace::DeadlineChange, type: :model do
  subject { build(:brightspace_deadline_change) }

  it { is_expected.to belong_to(:assignment) }
  it { is_expected.to validate_inclusion_of(:field).in_array(described_class::FIELDS) }
  it { is_expected.to validate_presence_of(:detected_at) }

  it "lists changes that wait for a notification" do
    pending_change = create(:brightspace_deadline_change)
    create(:brightspace_deadline_change, notified_at: Time.current)

    expect(described_class.pending_notification).to contain_exactly(pending_change)
  end
end

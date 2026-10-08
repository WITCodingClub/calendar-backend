# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: brightspace_assignment_preferences
#
#  id              :bigint           not null, primary key
#  due_at_override :datetime
#  progress        :string           default("not_started"), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  assignment_id   :bigint           not null
#  user_id         :bigint           not null
#
# Indexes
#
#  index_brightspace_assignment_preferences_on_assignment_id  (assignment_id) UNIQUE
#  index_brightspace_assignment_preferences_on_user_id        (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (assignment_id => brightspace_assignments.id)
#  fk_rails_...  (user_id => users.id)
#
RSpec.describe Brightspace::AssignmentPreference, type: :model do
  subject { create(:brightspace_assignment_preference) }

  it { is_expected.to belong_to(:user) }
  it { is_expected.to belong_to(:assignment) }
  it { is_expected.to validate_inclusion_of(:progress).in_array(described_class::PROGRESSES) }
  it { is_expected.to validate_uniqueness_of(:assignment_id) }

  # A check across two associations, which no matcher covers.
  it "rejects an assignment of another user" do
    preference = build(:brightspace_assignment_preference, user: create(:user))

    expect(preference).not_to be_valid
    expect(preference.errors[:assignment]).to include("is not one of your assignments")
  end

  it "raises the class version when saved" do
    assignment = create(:brightspace_assignment)
    offering = assignment.course_offering

    expect { create(:brightspace_assignment_preference, assignment: assignment) }
      .to change { offering.reload.version }
  end

  it "does not fail when the class is deleted with it" do
    preference = create(:brightspace_assignment_preference)

    expect { preference.course_offering.connection.user.destroy! }.not_to raise_error
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe RegistrationPlanPolicy do
  let(:user) { create(:user) }

  def policy(record, as: user) = described_class.new(as, record)

  it "lets a student see and change only their own plans" do
    mine = build(:registration_plan, user: user)
    other = build(:registration_plan)

    expect(policy(mine)).to have_attributes(show?: true, create?: true, update?: true, destroy?: true)
    expect(policy(other)).to have_attributes(show?: false, create?: false, update?: false, destroy?: false)
  end

  it "lets a signed-in user list plans, and no one without a user" do
    expect(policy(RegistrationPlan)).to have_attributes(index?: true)
    expect(policy(RegistrationPlan, as: nil)).to have_attributes(index?: false)
  end

  it "scopes plans to the student" do
    mine = create(:registration_plan, user: user)
    create(:registration_plan)

    expect(described_class::Scope.new(user, RegistrationPlan).resolve).to contain_exactly(mine)
  end
end

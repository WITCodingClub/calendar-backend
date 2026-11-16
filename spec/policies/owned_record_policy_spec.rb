# frozen_string_literal: true

require "rails_helper"

RSpec.describe OwnedRecordPolicy do
  let(:owner)  { create(:user) }
  let(:record) { create(:calendar_preference, user: owner) }

  def permissions(user)
    policy = described_class.new(user, record)
    %i[show? update? destroy?].index_with { |query| policy.public_send(query) }
  end

  it "lets the user who owns the record read, change and delete it" do
    expect(permissions(owner)).to eq(show?: true, update?: true, destroy?: true)
  end

  it "lets an admin read, and a super admin change and delete" do
    expect(permissions(create(:user, :admin))).to eq(show?: true, update?: false, destroy?: false)
    expect(permissions(create(:user, :super_admin))).to eq(show?: true, update?: true, destroy?: true)
  end

  it "refuses another user and a guest" do
    expect(permissions(create(:user)).values).to all(be(false))
    expect(permissions(nil).values).to all(be(false))
  end

  it "scopes a user to their own rows and an admin to every row" do
    other = create(:calendar_preference)

    expect(described_class::Scope.new(owner, CalendarPreference).resolve).to contain_exactly(record)
    expect(described_class::Scope.new(create(:user, :admin), CalendarPreference).resolve).to include(record, other)
  end
end

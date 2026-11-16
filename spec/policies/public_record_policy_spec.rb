# frozen_string_literal: true

require "rails_helper"

RSpec.describe PublicRecordPolicy do
  let(:record) { build(:term) }

  def permissions(user)
    policy = described_class.new(user, record)
    %i[show? create? destroy?].index_with { |query| policy.public_send(query) }
  end

  it "lets anyone read, admins change, and super admins delete" do
    expect(permissions(nil)).to eq(show?: true, create?: false, destroy?: false)
    expect(permissions(build(:user, :admin))).to eq(show?: true, create?: true, destroy?: false)
    expect(permissions(build(:user, :super_admin))).to eq(show?: true, create?: true, destroy?: true)
  end

  it "scopes to every row" do
    term = create(:term)

    expect(described_class::Scope.new(nil, Term).resolve).to include(term)
  end
end

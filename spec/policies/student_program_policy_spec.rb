# frozen_string_literal: true

require "rails_helper"

RSpec.describe StudentProgramPolicy do
  let(:user) { create(:user) }

  def policy(record, as: user) = described_class.new(as, record)

  it "lets a student create and destroy only their own planned rows" do
    planned = build(:student_program, :planned, user: user)
    leopardweb = build(:student_program, user: user)
    other = build(:student_program, :planned)

    expect(policy(planned)).to have_attributes(create?: true, destroy?: true, show?: true)
    expect(policy(leopardweb)).to have_attributes(create?: false, destroy?: false, show?: true)
    expect(policy(other)).to have_attributes(create?: false, destroy?: false, show?: false)
  end

  it "lets a student correct only their own active rows" do
    expect(policy(build(:student_program, user: user))).to have_attributes(update?: true)
    expect(policy(build(:student_program, :ended, user: user))).to have_attributes(update?: false)
    expect(policy(build(:student_program, :planned, user: user))).to have_attributes(update?: false)
    expect(policy(build(:student_program))).to have_attributes(update?: false)
  end

  it "lets a student pick the plan of their own active and planned rows, not of ended rows" do
    expect(policy(build(:student_program, user: user))).to have_attributes(update_plan?: true)
    expect(policy(build(:student_program, :planned, user: user))).to have_attributes(update_plan?: true)
    expect(policy(build(:student_program, :ended, user: user))).to have_attributes(update_plan?: false)
    expect(policy(build(:student_program))).to have_attributes(update_plan?: false)
  end

  it "scopes rows to the student" do
    mine = create(:student_program, user: user)
    create(:student_program)

    expect(described_class::Scope.new(user, StudentProgram).resolve).to contain_exactly(mine)
  end
end

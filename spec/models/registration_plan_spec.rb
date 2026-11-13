# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: registration_plans
#
#  id          :bigint           not null, primary key
#  courses     :jsonb            not null
#  preferences :jsonb            not null
#  term_uid    :integer          not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  user_id     :bigint           not null
#
# Indexes
#
#  index_registration_plans_on_term_uid              (term_uid)
#  index_registration_plans_on_user_id_and_term_uid  (user_id,term_uid) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (term_uid => terms.uid) ON DELETE => cascade
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
RSpec.describe RegistrationPlan, type: :model do
  subject { create(:registration_plan) }

  it { is_expected.to belong_to(:user) }
  it { is_expected.to belong_to(:term) }
  it { is_expected.to validate_uniqueness_of(:term_uid).scoped_to(:user_id) }

  def course(code: "COMP 3350", crns: [ "20410" ], fills: nil)
    { "code" => code, "crns" => crns, "fills" => fills }
  end

  def errors_for(**attributes)
    plan = build(:registration_plan, **attributes)
    plan.validate
    plan.errors.full_messages
  end

  # The shape of the courses entries is a custom validation. No matcher
  # covers a jsonb column.
  describe "courses" do
    it "keeps only code, crns, and fills, and stores each CRN as a string" do
      plan = build(:registration_plan, courses: [ { code: "COMP 3350", crns: [ 20410, "20411" ], extra: "x",
                                                    fills: { kind: "course", label: "Algorithms", other: 1 } } ])

      expect(plan).to be_valid
      expect(plan.courses).to eq([ { "code" => "COMP 3350", "crns" => [ "20410", "20411" ],
                                     "fills" => { "kind" => "course", "label" => "Algorithms" } } ])
    end

    it "stores one CRN in one spelling, so the list counts it one time" do
      plan = build(:registration_plan, courses: [ course(crns: [ 20410, "020410" ]), course(code: "MATH 2300", crns: [ "20410" ]) ])

      expect(plan.courses.first["crns"]).to eq(%w[20410 20410])
      expect(plan.crns).to eq([ "20410" ])
    end

    it "needs a list of 1 to 15 courses" do
      expect(errors_for(courses: nil)).to include("Courses must be a list of 1 to 15 courses")
      expect(errors_for(courses: [])).to include("Courses must be a list of 1 to 15 courses")
      expect(errors_for(courses: Array.new(16) { |i| course(crns: [ (20_000 + i).to_s ]) }))
        .to include("Courses must be a list of 1 to 15 courses")
      expect(errors_for(courses: Array.new(15) { |i| course(crns: [ (20_000 + i).to_s ]) })).to be_empty
    end

    it "rejects a CRN that is not digits, and too many CRNs" do
      expect(errors_for(courses: [ course(crns: [ "2041a" ]) ])).to include("Courses entry 1 has a CRN that is not digits")
      expect(errors_for(courses: [ course(crns: []) ])).to include("Courses entry 1 needs 1 to 4 CRNs")
      expect(errors_for(courses: [ course(crns: %w[1 2 3 4 5]) ])).to include("Courses entry 1 needs 1 to 4 CRNs")

      many = Array.new(8) { |i| course(crns: Array.new(4) { |j| (20_000 + (i * 4) + j).to_s }) }
      expect(errors_for(courses: many)).to include("Courses can name at most 30 CRNs")
    end

    it "bounds the code and the fills label" do
      expect(errors_for(courses: [ "COMP 3350" ])).to include("Courses entry 1 must be an object")
      expect(errors_for(courses: [ course(code: "C" * 21) ])).to include(a_string_including("entry 1 needs a code"))
      expect(errors_for(courses: [ course(fills: { "kind" => "course", "label" => "L" * 201 }) ]))
        .to include(a_string_including("entry 1 needs fills"))
      expect(errors_for(courses: [ course(fills: { "kind" => "course" }) ])).to include(a_string_including("needs fills"))
      expect(errors_for(courses: [ course(fills: "Algorithms") ])).to include(a_string_including("needs fills"))
    end
  end

  # A custom validation: no matcher measures the JSON size.
  it "needs preferences as an object of at most 2048 bytes" do
    expect(errors_for(preferences: [ 1 ])).to include("Preferences must be an object")
    expect(errors_for(preferences: { "note" => "x" * 2_100 })).to include("Preferences must be at most 2048 bytes of JSON")
    expect(build(:registration_plan, preferences: nil).preferences).to eq({})
  end

  it "lists the CRNs in order, each one time, and the course codes" do
    plan = build(:registration_plan, courses: [ course(code: "COMP 3350", crns: %w[20410 20411]),
                                                course(code: "MATH 2300", crns: %w[20411 20520]) ])

    expect(plan.crns).to eq(%w[20410 20411 20520])
    expect(plan.course_codes).to eq([ "COMP 3350", "MATH 2300" ])
    expect(plan.course_count).to eq(2)
  end

  it "finds the plans before a term, newest first" do
    user = create(:user)
    fall = create(:registration_plan, user: user, term: create(:term, uid: 202610, year: 2025, season: :fall))
    spring = create(:registration_plan, user: user, term: create(:term, uid: 202620, year: 2026, season: :spring))
    create(:registration_plan, user: user, term: create(:term, uid: 202710, year: 2026, season: :fall))

    expect(user.registration_plans.before_term(202710).newest_first).to eq([ spring, fall ])
  end

  it "is deleted with the user" do
    plan = create(:registration_plan)

    plan.user.destroy!

    expect(described_class.exists?(plan.id)).to be(false)
  end
end

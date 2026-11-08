# frozen_string_literal: true

require "rails_helper"

RSpec.describe AcademicProfiles::StudentCorrection do
  let(:user) { create(:user) }
  let!(:profile) do
    create(:academic_profile, user: user, level: "Undergraduate", class_standing: "Sophomore", admit_term_uid: 202610,
                              leopardweb_programs_digest: "lw")
  end
  let!(:major) do
    create(:student_program, user: user, name: "Widget Design", code: "BWDG", degree: "Bachelor of Science",
                             department: "Widgets", catalog_term_uid: 202610)
  end
  let!(:minor) { create(:student_program, :minor, user: user, name: "Gears", catalog_term_uid: 202620) }

  subject(:correction) { described_class.new(user) }

  it "changes a profile field and keeps the other fields and the programs" do
    correction.profile!(class_standing: "Junior")

    expect(profile.reload).to have_attributes(class_standing: "Junior", level: "Undergraduate", admit_term_uid: 202610)
    expect(user.student_programs.active).to contain_exactly(major, minor)
  end

  it "keeps the LeopardWeb source of every program on a profile correction" do
    correction.profile!(class_standing: "Junior")

    expect([ major.reload.source, minor.reload.source ]).to eq(%w[leopardweb leopardweb])
  end

  it "has no way to change a program" do
    expect(correction).not_to respond_to(:program!)
  end
end

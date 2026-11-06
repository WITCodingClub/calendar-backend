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

  it "changes a field that does not name the program in place, with source student" do
    correction.program!(major, department: "Gadgets")

    expect(major.reload).to have_attributes(department: "Gadgets", source: "student", status: "active")
    expect(minor.reload).to have_attributes(status: "active", name: "Gears")
  end

  it "ends the row and adds a new one when the catalog term changes, so the history stays" do
    correction.program!(major, catalog_term: "Spring 2026")

    expect(major.reload).to have_attributes(status: "ended")
    expect(user.student_programs.active.find_by(name: "Widget Design"))
      .to have_attributes(catalog_term_uid: 202620, source: "student", code: "BWDG")
  end

  it "leaves the LeopardWeb digests as they are, so a LeopardWeb sync with the same list keeps the change" do
    correction.program!(major, department: "Gadgets")

    expect(profile.reload.leopardweb_programs_digest).to eq("lw")
  end

  it "rejects a bad term without a change" do
    expect { correction.program!(major, catalog_term: "Winter 2025") }
      .to raise_error(AcademicProfiles::InvalidProfileError, /catalog_term/)
    expect(major.reload).to have_attributes(status: "active", catalog_term_uid: 202610)
  end

  it "rejects an ended row or another student's row" do
    ended = create(:student_program, :ended, user: user)

    expect { correction.program!(ended, name: "X") }.to raise_error(AcademicProfiles::InvalidProfileError)
    expect { correction.program!(create(:student_program), name: "X") }.to raise_error(AcademicProfiles::InvalidProfileError)
  end

  it "never changes a planned program" do
    planned = create(:student_program, :planned, user: user)

    correction.program!(major, department: "Gadgets")

    expect(planned.reload).to have_attributes(status: "planned")
  end
end

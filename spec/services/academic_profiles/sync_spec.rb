# frozen_string_literal: true

require "rails_helper"

RSpec.describe AcademicProfiles::Sync do
  let(:user) { create(:user) }

  let(:major) do
    { role: "major", code: "BCOS3", name: "Computer Science", degree: "Bachelor of Science",
      department: "Computer Science & Networking", catalog_term: "Fall 2025" }
  end
  let(:minor) { { role: "minor", name: "Computer Networking", catalog_term: "Fall 2025" } }

  def payload(programs: [ major, minor ], source: "leopardweb", **profile)
    { source: source, level: "Undergraduate", class_standing: "Sophomore", admit_term: "Fall 2025",
      programs: programs }.merge(profile)
  end

  def sync(**) = described_class.new(user, payload(**)).call

  it "stores the profile and one active row for each program" do
    profile = sync

    expect(profile).to have_attributes(level: "Undergraduate", class_standing: "Sophomore", admit_term_uid: 202610)
    expect(profile.leopardweb_digest).to be_present
    expect(user.student_programs.active.pluck(:role, :code, :name, :catalog_term_uid, :source))
      .to contain_exactly([ "major", "BCOS3", "Computer Science", 202610, "leopardweb" ],
                          [ "minor", nil, "Computer Networking", 202610, "leopardweb" ])
  end

  it "keeps the row of a program that is still in the list, and updates its other fields" do
    sync
    row = user.student_programs.find_by!(role: "major")

    sync(programs: [ major.merge(department: "School of Computing") ], class_standing: "Junior")

    expect(row.reload).to have_attributes(status: "active", department: "School of Computing")
    expect(user.academic_profile.class_standing).to eq("Junior")
  end

  it "ends a program that leaves the list and keeps its row" do
    sync
    new_major = major.merge(code: "BMEC1", name: "Mechanical Engineering", catalog_term: "Spring 2027")

    sync(programs: [ new_major ])

    expect(user.student_programs.ended.pluck(:name)).to contain_exactly("Computer Science", "Computer Networking")
    expect(user.student_programs.ended.pluck(:ended_at)).to all(be_present)
    expect(user.student_programs.active.pluck(:name, :catalog_term_uid)).to eq([ [ "Mechanical Engineering", 202720 ] ])
  end

  it "keeps a value the student changed when LeopardWeb sends the same profile again" do
    sync
    sync(source: "student", class_standing: "Junior", programs: [ major, minor.merge(name: "Data Science") ])

    sync

    expect(user.academic_profile.reload.class_standing).to eq("Junior")
    expect(user.student_programs.active.pluck(:name, :source))
      .to contain_exactly([ "Computer Science", "student" ], [ "Data Science", "student" ])
  end

  it "applies a LeopardWeb profile that changed after the student's edit" do
    sync
    sync(source: "student", class_standing: "Junior")

    sync(class_standing: "Senior")

    expect(user.academic_profile.reload.class_standing).to eq("Senior")
    expect(user.student_programs.active.pluck(:source).uniq).to eq([ "leopardweb" ])
  end

  it "accepts an empty list and a profile with no terms" do
    profile = sync(programs: [], admit_term: nil)

    expect(profile.admit_term_uid).to be_nil
    expect(user.student_programs).to be_empty
  end

  describe "invalid payloads" do
    it "rejects a term it cannot read with the invalid_term code" do
      expect { sync(admit_term: "Autumn 2025") }
        .to raise_error(AcademicProfiles::InvalidProfileError) { |error| expect(error.code).to eq("invalid_term") }
    end

    it "rejects an unknown source, role, or a program with no name" do
      expect { sync(source: "banner") }.to raise_error(AcademicProfiles::InvalidProfileError, /source/)
      expect { sync(programs: [ major.merge(role: "double") ]) }
        .to raise_error(AcademicProfiles::InvalidProfileError, /role/)
      expect { sync(programs: [ major.merge(name: " ") ]) }
        .to raise_error(AcademicProfiles::InvalidProfileError, /name is required/)
    end

    it "rejects a value that is not a string, or a list that is too long" do
      expect { sync(level: 3) }.to raise_error(AcademicProfiles::InvalidProfileError, /level must be a string/)
      expect { sync(programs: [ "Computer Science" ]) }
        .to raise_error(AcademicProfiles::InvalidProfileError, /must be an object/)
      expect { sync(programs: Array.new(11) { major }) }
        .to raise_error(AcademicProfiles::InvalidProfileError, /at most 10/)
    end

    it "writes nothing" do
      expect { sync(programs: [ major, minor.merge(catalog_term: "Fall") ]) }
        .to raise_error(AcademicProfiles::InvalidProfileError)

      expect(AcademicProfile.count + StudentProgram.count).to eq(0)
    end
  end
end

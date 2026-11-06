# frozen_string_literal: true

require "rails_helper"

RSpec.describe AcademicProfiles::PlannedPrograms do
  let(:user) { create(:user) }
  let!(:older_year) { create(:catalog_year, :imported, start_year: 2024) }
  let!(:newest_year) { create(:catalog_year, :imported, start_year: 2026) }
  let(:minor) { create(:degree_program, :minor, slug: "gear-minor", name: "Gear Minor") }
  let(:planned) { described_class.new(user) }

  before do
    create(:requirement_set, degree_program: minor, catalog_year: older_year, name: "Gear Minor",
                             school_name: "School of Engineering", department_name: "Mechanical")
    create(:requirement_set, degree_program: minor, catalog_year: newest_year, name: "Gear Minor")
  end

  def error_code
    yield
  rescue AcademicProfiles::InvalidProfileError => e
    e.code
  end

  describe "#build" do
    it "builds a planned row from the newest catalog year, with the role from the program kind" do
      row = planned.build(program: "gear-minor")

      expect(row).to be_new_record
      expect(row).to have_attributes(status: "planned", source: "student", role: "minor", name: "Gear Minor",
                                     degree_program: minor, catalog_year: newest_year, catalog_term_uid: nil)
    end

    it "takes a catalog year or a start term, and copies the school and department of that year" do
      row = planned.build(program: "gear-minor", catalog_year: "Spring 2025")

      expect(row).to have_attributes(catalog_year: older_year, college: "School of Engineering", department: "Mechanical")
    end

    it "makes a bachelor's program a major" do
      major = create(:degree_program, slug: "widget-design-bs")
      create(:requirement_set, degree_program: major, catalog_year: newest_year)

      expect(planned.build(program: "widget-design-bs").role).to eq("major")
    end

    it "refuses a missing program, an unknown program, and an unknown or malformed catalog year" do
      expect(error_code { planned.build(program: "") }).to eq("invalid_profile")
      expect(error_code { planned.build(program: "basket-weaving-bs") }).to eq("unknown_program")
      expect(error_code { planned.build(program: "gear-minor", catalog_year: "2016-2017") }).to eq("unknown_catalog_year")
      expect(error_code { planned.build(program: "gear-minor", catalog_year: "someday") }).to eq("invalid_catalog_year")
    end

    it "refuses a program the student has as an active or planned program" do
      create(:student_program, :minor, user: user, degree_program: minor)

      expect(error_code { planned.build(program: "gear-minor") }).to eq("duplicate_program")
    end

    it "allows a program the student ended, such as a major they changed" do
      create(:student_program, :minor, :ended, user: user, degree_program: minor)

      expect(planned.build(program: "gear-minor")).to be_valid
    end

    it "refuses more than MAX_PLANNED planned programs" do
      create_list(:student_program, described_class::MAX_PLANNED, :planned, catalog_year: newest_year, user: user)

      expect(error_code { planned.build(program: "gear-minor") }).to eq("too_many_programs")
    end
  end

  describe "#find" do
    it "finds a planned row of the user by public id or by program slug" do
      row = create(:student_program, :planned, catalog_year: newest_year, user: user, degree_program: minor)

      expect(planned.find(row.public_id)).to eq(row)
      expect(planned.find("GEAR-MINOR")).to eq(row)
    end

    it "does not find another user's row, a LeopardWeb row, or a blank key" do
      other = create(:student_program, :planned, catalog_year: newest_year, degree_program: minor)
      active = create(:student_program, user: user, degree_program: minor)

      expect(planned.find(other.public_id)).to be_nil
      expect(planned.find(active.public_id)).to be_nil
      expect(planned.find("gear-minor")).to be_nil
      expect(planned.find(" ")).to be_nil
    end
  end

  it "keeps planned rows when a LeopardWeb sync replaces the program list" do
    row = create(:student_program, :planned, catalog_year: newest_year, user: user, degree_program: minor)
    create(:student_program, user: user, name: "Old Major")

    AcademicProfiles::Sync.new(user, source: "leopardweb", programs: []).call

    expect(row.reload).to have_attributes(status: "planned", ended_at: nil)
    expect(user.student_programs.ended.pluck(:name)).to eq([ "Old Major" ])
  end
end

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

  describe "#save!" do
    it "saves a built row" do
      row = planned.save!(planned.build(program: "gear-minor"))

      expect(row).to be_persisted
    end

    # Two adds of the same program at the same time both pass the check in
    # build. The check in save! runs again under the lock.
    it "checks again before it saves, so a second add of the same program fails" do
      first = planned.build(program: "gear-minor")
      second = described_class.new(user).build(program: "gear-minor")
      planned.save!(first)

      expect(error_code { planned.save!(second) }).to eq("duplicate_program")
      expect(user.student_programs.planned.count).to eq(1)
    end
  end

  describe "#find" do
    it "finds a planned row of the user by public id or by program slug" do
      row = create(:student_program, :planned, catalog_year: newest_year, user: user, degree_program: minor)

      expect(planned.find(row.public_id)).to eq(row)
      expect(planned.find("GEAR-MINOR")).to eq(row)
    end

    it "finds a row by the old slug of a renamed program" do
      stub_const("DegreeProgram::RENAMED_SLUGS", { "gear-design-minor" => "gear-minor" })
      row = create(:student_program, :planned, catalog_year: newest_year, user: user, degree_program: minor)

      expect(planned.find("gear-design-minor")).to eq(row)
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

  describe "pathways" do
    let(:bachelor) { create(:degree_program, slug: "gear-studies-bs", name: "Gear Studies, B.S.") }
    let(:master) { create(:degree_program, :master, slug: "gear-studies-ms", name: "Gear Studies, M.S.") }
    let!(:pathway) do
      create(:program_pathway, slug: "gear-studies-4-plus-1", name: "Gear Studies 4+1").tap do |record|
        create(:program_pathway_step, program_pathway: record, degree_program: bachelor, position: 1)
        create(:program_pathway_step, program_pathway: record, degree_program: master, position: 2, plan_years: 1)
      end
    end

    before do
      create(:requirement_set, degree_program: bachelor, catalog_year: newest_year, name: "Gear Studies, B.S.")
      create(:requirement_set, degree_program: master, catalog_year: newest_year, name: "Gear Studies, M.S.")
    end

    it "plans only the programs the student does not have, each linked to the pathway" do
      create(:student_program, user: user, degree_program: bachelor)

      record, rows = planned.build_pathway(pathway: "Gear-Studies-4-plus-1")
      planned.save_pathway!(record, rows)

      expect(record).to eq(pathway)
      expect(user.student_programs.planned.sole)
        .to have_attributes(degree_program: master, program_pathway: pathway, role: "major", catalog_year: newest_year)
    end

    it "refuses an unknown or inactive pathway with the list of slugs, a pathway planned twice, and one with nothing to add" do
      create(:program_pathway, slug: "retired-4-plus-1", active: false)

      expect(error_code { planned.build_pathway(pathway: "retired-4-plus-1") }).to eq("unknown_pathway")
      ProgramPathway.update_all(active: false)
      expect { planned.build_pathway(pathway: "nope") }.to raise_error(AcademicProfiles::InvalidProfileError, /no program pathways yet/)
      pathway.reload.update!(active: true)
      expect { planned.build_pathway(pathway: "nope") }.to raise_error(AcademicProfiles::InvalidProfileError, /Pathways: gear-studies-4-plus-1\z/)

      planned.save_pathway!(*planned.build_pathway(pathway: "gear-studies-4-plus-1"))
      expect(error_code { planned.build_pathway(pathway: "gear-studies-4-plus-1") }).to eq("duplicate_pathway")

      other = described_class.new(create(:user))
      create(:student_program, user: other.user, degree_program: bachelor)
      create(:student_program, :planned, user: other.user, degree_program: master, catalog_year: newest_year)
      expect(error_code { other.build_pathway(pathway: "gear-studies-4-plus-1") }).to eq("duplicate_pathway")
    end

    it "refuses a pathway that would pass MAX_PLANNED, and a step program missing from the catalog year" do
      create_list(:student_program, described_class::MAX_PLANNED - 1, :planned, catalog_year: newest_year, user: user)
      expect(error_code { planned.build_pathway(pathway: "gear-studies-4-plus-1") }).to eq("too_many_programs")

      expect(error_code { described_class.new(create(:user)).build_pathway(pathway: "gear-studies-4-plus-1", catalog_year: "2024-2025") })
        .to eq("unknown_program")
    end

    it "checks again under the lock, so a second add of the same pathway saves nothing" do
      first = planned.build_pathway(pathway: "gear-studies-4-plus-1")
      second = described_class.new(user).build_pathway(pathway: "gear-studies-4-plus-1")
      planned.save_pathway!(*first)

      expect(error_code { planned.save_pathway!(*second) }).to eq("duplicate_program")
      expect(user.student_programs.planned.count).to eq(2)
    end

    it "finds the planned rows of a pathway, and not a program the student planned alone" do
      alone = create(:student_program, :planned, user: user, degree_program: bachelor, catalog_year: newest_year)
      planned.save_pathway!(*planned.build_pathway(pathway: "gear-studies-4-plus-1"))

      record, rows = planned.find_pathway("gear-studies-4-plus-1")

      expect(record).to eq(pathway)
      expect(rows.map(&:degree_program)).to eq([ master ])
      expect(rows).not_to include(alone)
      expect(planned.find_pathway("nope")).to be_nil
    end

    describe "a Double Leopard pathway" do
      let!(:leopard) do
        create(:program_pathway, :double_leopard, slug: "double-leopard-gear-studies-ms").tap do |record|
          create(:program_pathway_step, program_pathway: record, degree_program: master, position: 1, plan_years: nil)
        end
      end

      it "plans the master's after any bachelor's the student has, from the catalog or from LeopardWeb" do
        other_bachelor = create(:degree_program, slug: "widget-design-bs")
        create(:student_program, :planned, user: user, degree_program: other_bachelor, catalog_year: newest_year)

        planned.save_pathway!(*planned.build_pathway(pathway: "double-leopard-gear-studies-ms"))
        expect(user.student_programs.planned.where(program_pathway: leopard).map(&:degree_program)).to eq([ master ])

        leopardweb = described_class.new(create(:user))
        create(:student_program, user: leopardweb.user, degree_program: nil, degree: "Bachelor of Science")
        expect(leopardweb.build_pathway(pathway: "double-leopard-gear-studies-ms").last.map(&:degree_program)).to eq([ master ])
      end

      it "refuses a student with no bachelor's program" do
        create(:student_program, user: user, degree_program: master)
        create(:student_program, :ended, user: user, degree_program: bachelor)

        expect(error_code { planned.build_pathway(pathway: "double-leopard-gear-studies-ms") }).to eq("no_bachelors_program")
      end
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

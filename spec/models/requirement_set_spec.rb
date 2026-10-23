# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: requirement_sets
#
#  id                :bigint           not null, primary key
#  department_name   :string
#  description       :text
#  fetched_at        :datetime
#  last_seen_at      :datetime
#  name              :string           not null
#  needs_review      :boolean          default(FALSE), not null
#  path              :string
#  school_name       :string
#  source            :string           default("html"), not null
#  source_digest     :string
#  total_credits     :integer
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  catalog_year_id   :bigint           not null
#  degree_program_id :bigint           not null
#
# Indexes
#
#  idx_on_degree_program_id_catalog_year_id_10cd4884bd  (degree_program_id,catalog_year_id) UNIQUE
#  index_requirement_sets_on_catalog_year_id            (catalog_year_id)
#
# Foreign Keys
#
#  fk_rails_...  (catalog_year_id => catalog_years.id)
#  fk_rails_...  (degree_program_id => degree_programs.id)
#
RSpec.describe RequirementSet do
  subject { create(:requirement_set) }

  it { is_expected.to belong_to(:degree_program) }
  it { is_expected.to belong_to(:catalog_year) }
  it { is_expected.to have_many(:program_plans).dependent(:delete_all) }
  it { is_expected.to have_many(:elective_groups).dependent(:delete_all) }
  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to validate_uniqueness_of(:degree_program_id).scoped_to(:catalog_year_id) }

  it do
    expect(subject).to define_enum_for(:source).with_values(html: "html", wayback: "wayback", pdf: "pdf")
                                               .backed_by_column_of_type(:string).with_prefix.validating
  end

  it "lists its plans in page order" do
    second = create(:program_plan, requirement_set: subject, position: 2)
    first = create(:program_plan, requirement_set: subject, position: 1)

    expect(subject.program_plans).to eq([ first, second ])
  end

  describe "#standard_plan" do
    it "picks the first plan that is not accelerated" do
      create(:program_plan, :accelerated, requirement_set: subject, position: 1)
      four_year = create(:program_plan, requirement_set: subject, position: 2)

      expect(subject.standard_plan).to eq(four_year)
    end

    it "picks the first plan when every plan is accelerated" do
      three_year = create(:program_plan, :accelerated, requirement_set: subject, position: 1)

      expect(subject.standard_plan).to eq(three_year)
    end

    it "returns nil for a program with no plan, such as a minor" do
      expect(subject.standard_plan).to be_nil
    end
  end

  it "deletes its plans, their rows, and its elective lists with it" do
    plan = create(:program_plan, requirement_set: subject)
    create(:program_plan_item, program_plan: plan)
    create(:elective_group_course, elective_group: create(:elective_group, requirement_set: subject))

    expect { subject.destroy }.to change(ProgramPlanItem, :count).by(-1)
      .and change(ElectiveGroupCourse, :count).by(-1)
  end

  describe "#listed?" do
    let(:catalog_year) { create(:catalog_year, :imported) }

    it "is true for a set the last import saw, and false for an older one" do
      expect(create(:requirement_set, catalog_year: catalog_year)).to be_listed
      expect(create(:requirement_set, :unlisted, catalog_year: catalog_year)).not_to be_listed
      expect(create(:requirement_set, catalog_year: catalog_year, last_seen_at: nil)).not_to be_listed
    end

    it "is true in a year that has no finished import" do
      expect(create(:requirement_set, :unlisted, catalog_year: create(:catalog_year))).to be_listed
    end
  end

  describe "#catalog_url" do
    it "links to the catalog site" do
      set = build(:requirement_set, path: "/previous-catalogs/2024-2025/widgetry/widget-design-bs/")

      expect(set.catalog_url).to eq("https://catalog.wit.edu/previous-catalogs/2024-2025/widgetry/widget-design-bs/")
    end

    it "links to the Wayback capture for a year read from the Wayback Machine" do
      set = build(:requirement_set, source: "wayback", path: "/widgetry/widget-design-bs/",
                                    catalog_year: build(:catalog_year, start_year: 2025))

      expect(set.catalog_url)
        .to eq("https://web.archive.org/web/20260301000000/https://catalog.wit.edu/widgetry/widget-design-bs/")
    end

    it "is nil with no path" do
      expect(build(:requirement_set, path: nil).catalog_url).to be_nil
    end
  end
end

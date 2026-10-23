# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: program_plan_items
#
#  id                :bigint           not null, primary key
#  course_number     :integer
#  footnote          :string
#  kind              :string           not null
#  lab_hours         :integer
#  label             :string
#  lecture_hours     :integer
#  max_credits       :integer
#  min_credits       :integer
#  options           :jsonb            not null
#  position          :integer          not null
#  season            :string           not null
#  subject_code      :string
#  year_index        :integer          not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  catalog_course_id :bigint
#  elective_group_id :bigint
#  program_plan_id   :bigint           not null
#
# Indexes
#
#  index_program_plan_items_on_catalog_course_id               (catalog_course_id)
#  index_program_plan_items_on_elective_group_id               (elective_group_id)
#  index_program_plan_items_on_program_plan_id_and_position    (program_plan_id,position) UNIQUE
#  index_program_plan_items_on_subject_code_and_course_number  (subject_code,course_number)
#
# Foreign Keys
#
#  fk_rails_...  (catalog_course_id => catalog_courses.id) ON DELETE => nullify
#  fk_rails_...  (elective_group_id => elective_groups.id) ON DELETE => nullify
#  fk_rails_...  (program_plan_id => program_plans.id) ON DELETE => cascade
#
RSpec.describe ProgramPlanItem do
  subject { create(:program_plan_item) }

  it { is_expected.to belong_to(:program_plan) }
  it { is_expected.to belong_to(:elective_group).optional }
  it { is_expected.to belong_to(:catalog_course).optional }
  it { is_expected.to validate_presence_of(:year_index) }
  it { is_expected.to validate_numericality_of(:year_index).only_integer.is_greater_than_or_equal_to(1) }
  it { is_expected.to validate_presence_of(:position) }
  it { is_expected.to validate_uniqueness_of(:position).scoped_to(:program_plan_id) }
  it { is_expected.to validate_presence_of(:subject_code) }
  it { is_expected.to validate_presence_of(:course_number) }

  it do
    expect(subject).to define_enum_for(:season).with_values(fall: "fall", spring: "spring", summer: "summer")
                                               .backed_by_column_of_type(:string).validating
  end

  it do
    expect(subject).to define_enum_for(:kind).with_values(course: "course", placeholder: "placeholder", choice: "choice")
                                             .backed_by_column_of_type(:string).validating
  end

  context "when it is a placeholder" do
    subject { build(:program_plan_item, :placeholder) }

    it { is_expected.to validate_presence_of(:label) }
    it { is_expected.not_to validate_presence_of(:subject_code) }
  end

  # A custom validation on a JSON column, so no matcher covers it.
  describe "choice options" do
    it "accepts two or more courses" do
      expect(build(:program_plan_item, :choice)).to be_valid
    end

    it "stores each option like the code columns" do
      item = build(:program_plan_item, :choice, options: [
        { "subject_code" => " comp ", "course_number" => "1000" },
        { subject_code: "COMP", course_number: 1099 }
      ])

      item.validate

      expect(item.options).to eq([ { "subject_code" => "COMP", "course_number" => 1000 },
                                   { "subject_code" => "COMP", "course_number" => 1099 } ])
    end

    it "rejects one course, an empty list, or a row with no number" do
      one = [ { "subject_code" => "COMP", "course_number" => 1000 } ]
      no_number = one + [ { "subject_code" => "COMP" } ]

      [ one, [], no_number, "COMP1000" ].each do |options|
        item = build(:program_plan_item, :choice, options: options)
        expect(item).not_to be_valid
        expect(item.errors[:options]).to be_present
      end
    end
  end

  describe "the course code" do
    it "is stored in capitals" do
      expect(create(:program_plan_item, subject_code: " comp ").subject_code).to eq("COMP")
    end

    it "is nil for a placeholder" do
      expect(build(:program_plan_item, :placeholder).code).to be_nil
    end

    it "reads like the catalog" do
      expect(build(:program_plan_item, subject_code: "COMP", course_number: 2350).code).to eq("COMP 2350")
    end
  end

  describe ".link_catalog_courses" do
    it "links each row to the Banner course with its code" do
      course = create(:catalog_course, subject_code: "COMP", course_number: 2350)
      item = create(:program_plan_item, subject_code: "COMP", course_number: 2350)
      unknown = create(:program_plan_item, subject_code: "COMP", course_number: 128)
      placeholder = create(:program_plan_item, :placeholder)

      expect(described_class.link_catalog_courses).to eq(1)
      expect(item.reload.catalog_course).to eq(course)
      expect(unknown.reload.catalog_course).to be_nil
      expect(placeholder.reload.catalog_course).to be_nil
    end

    it "changes nothing when every link is right" do
      create(:catalog_course, subject_code: "COMP", course_number: 2350)
      create(:program_plan_item, subject_code: "COMP", course_number: 2350)
      described_class.link_catalog_courses

      expect(described_class.link_catalog_courses).to eq(0)
    end

    it "fixes a link that a bulk write left on the old course" do
      old_course = create(:catalog_course, subject_code: "COMP", course_number: 1000)
      new_course = create(:catalog_course, subject_code: "COMP", course_number: 1050)
      item = create(:program_plan_item, subject_code: "COMP", course_number: 1000)
      described_class.link_catalog_courses
      item.update_columns(course_number: 1050)

      expect { described_class.link_catalog_courses }.to change { item.reload.catalog_course }.from(old_course).to(new_course)
    end

    it "clears a link when the new code is not in Banner" do
      create(:catalog_course, subject_code: "COMP", course_number: 1000)
      item = create(:program_plan_item, subject_code: "COMP", course_number: 1000)
      described_class.link_catalog_courses
      item.update_columns(course_number: 128)

      expect { described_class.link_catalog_courses }.to change { item.reload.catalog_course_id }.to(nil)
    end
  end

  # A save callback, so no matcher covers it.
  it "drops its link when its code changes" do
    course = create(:catalog_course, subject_code: "COMP", course_number: 1000)
    item = create(:program_plan_item, subject_code: "COMP", course_number: 1000, catalog_course: course)

    item.update!(course_number: 1050)

    expect(item.reload.catalog_course).to be_nil
  end

  # A cross-record check, so no matcher covers it.
  it "takes an elective list only from its own requirement set" do
    plan = create(:program_plan)
    own = create(:elective_group, requirement_set: plan.requirement_set)
    expect(build(:program_plan_item, :placeholder, program_plan: plan, elective_group: own)).to be_valid

    item = build(:program_plan_item, :placeholder, program_plan: plan, elective_group: create(:elective_group))
    expect(item).not_to be_valid
    expect(item.errors[:elective_group]).to be_present
  end

  # A comparison with another column, so the numericality matchers do not cover it.
  it "rejects a credit range that ends below its start" do
    item = build(:program_plan_item, min_credits: 4, max_credits: 3)

    expect(item).not_to be_valid
    expect(item.errors[:max_credits]).to be_present
  end
end

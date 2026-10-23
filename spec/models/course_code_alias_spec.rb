# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: course_code_aliases
#
#  id                 :bigint           not null, primary key
#  from_course_number :integer          not null
#  from_subject_code  :string           not null
#  note               :string
#  reviewed_at        :datetime
#  source             :string           not null
#  to_course_number   :integer          not null
#  to_subject_code    :string           not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#
# Indexes
#
#  idx_course_code_aliases_unique                      (from_subject_code,from_course_number,to_subject_code,to_course_number) UNIQUE
#  idx_on_to_subject_code_to_course_number_49e737555f  (to_subject_code,to_course_number)
#
RSpec.describe CourseCodeAlias do
  subject { create(:course_code_alias) }

  it { is_expected.to validate_presence_of(:from_subject_code) }
  it { is_expected.to validate_presence_of(:from_course_number) }
  it { is_expected.to validate_presence_of(:to_subject_code) }
  it { is_expected.to validate_presence_of(:to_course_number) }

  it do
    expect(subject).to validate_uniqueness_of(:to_course_number)
      .scoped_to(:from_subject_code, :from_course_number, :to_subject_code)
  end

  it do
    expect(subject).to define_enum_for(:source)
      .with_values(title_match: "title_match", banner: "banner", admin: "admin")
      .backed_by_column_of_type(:string).with_prefix.validating
  end

  it "reads both codes like the catalog" do
    row = build(:course_code_alias, from_subject_code: "comp", from_course_number: 128,
                                    to_subject_code: "COMP", to_course_number: 1000)

    row.validate

    expect([ row.from_code, row.to_code ]).to eq([ "COMP 128", "COMP 1000" ])
  end

  # A cross-field check, so no matcher covers it.
  it "rejects a code that points to itself" do
    row = build(:course_code_alias, from_subject_code: "COMP", from_course_number: 128,
                                    to_subject_code: "comp", to_course_number: 128)

    expect(row).not_to be_valid
    expect(row.errors[:to_course_number]).to be_present
  end

  # A check across rows, so no matcher covers it.
  it "rejects the reverse of a stored alias" do
    reverse = build(:course_code_alias, from_subject_code: subject.to_subject_code, from_course_number: subject.to_course_number,
                                        to_subject_code: subject.from_subject_code, to_course_number: subject.from_course_number)

    expect(reverse).not_to be_valid
    expect(reverse.errors[:base]).to be_present
    expect(subject).to be_valid
  end

  it "lists the reviewed rows" do
    reviewed = create(:course_code_alias, :reviewed)
    subject

    expect(described_class.reviewed).to eq([ reviewed ])
  end
end

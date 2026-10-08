# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: faculties
#
#  id                       :bigint           not null, primary key
#  department               :string
#  directory_last_synced_at :datetime
#  directory_raw_data       :jsonb
#  display_name             :string
#  email                    :string           not null
#  embedding                :vector(1536)
#  embedding_digest         :string(64)
#  employee_type            :string
#  first_name               :string           not null
#  last_name                :string           not null
#  middle_name              :string
#  office_location          :string
#  phone                    :string
#  photo_url                :string
#  rmp_raw_data             :jsonb
#  school                   :string
#  title                    :string
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  rmp_id                   :string
#
# Indexes
#
#  index_faculties_on_department                (department)
#  index_faculties_on_directory_last_synced_at  (directory_last_synced_at)
#  index_faculties_on_directory_raw_data        (directory_raw_data) USING gin
#  index_faculties_on_email                     (email) UNIQUE
#  index_faculties_on_embedding                 (embedding) USING hnsw
#  index_faculties_on_employee_type             (employee_type)
#  index_faculties_on_lower_email               (lower((email)::text))
#  index_faculties_on_rmp_id                    (rmp_id) UNIQUE
#  index_faculties_on_rmp_raw_data              (rmp_raw_data) USING gin
#  index_faculties_on_school                    (school)
#
RSpec.describe Faculty, type: :model do
  subject { create(:faculty) }

  it { is_expected.to have_many(:course_faculties).dependent(:destroy) }
  it { is_expected.to have_many(:courses).through(:course_faculties) }
  it { is_expected.to have_many(:rmp_ratings).dependent(:destroy) }
  it { is_expected.to have_many(:related_professors).dependent(:destroy) }
  it { is_expected.to have_one(:rating_distribution).dependent(:destroy) }
  it { is_expected.to have_many(:teacher_rating_tags).dependent(:destroy) }

  it { is_expected.to validate_presence_of(:email) }
  it { is_expected.to validate_uniqueness_of(:email) }
  it { is_expected.to validate_presence_of(:first_name) }
  it { is_expected.to validate_presence_of(:last_name) }
  it { is_expected.to validate_uniqueness_of(:rmp_id).allow_nil }

  describe "#similar_instructors" do
    let(:term) { create(:term) }

    def teaching_faculty(angle)
      person = give_embedding(create(:faculty), angle)
      create(:course, term: term).faculties << person
      person
    end

    it "returns the closest instructors who teach, nearest first" do
      source = teaching_faculty(0.0)
      near   = teaching_faculty(0.10)
      far    = teaching_faculty(0.90)

      expect(source.similar_instructors).to eq([ near, far ])
    end

    it "leaves out people who teach nothing" do
      source = teaching_faculty(0.0)
      give_embedding(create(:faculty), 0.01)

      expect(source.similar_instructors).to be_empty
    end

    it "stops at the limit" do
      source = teaching_faculty(0.0)
      teaching_faculty(0.10)
      teaching_faculty(0.20)

      expect(source.similar_instructors(limit: 1).length).to eq(1)
    end

    it "returns nothing until the instructor has a vector" do
      expect(create(:faculty).similar_instructors).to be_empty
    end
  end

  describe "#embedding_text" do
    it "reads the directory facts a student would search by" do
      faculty = create(:faculty, first_name: "Ada", last_name: "Lovelace", display_name: nil,
                                 title: "Professor", department: "Computer Science", school: "School of Computing")

      expect(faculty.embedding_text).to eq("Ada Lovelace. Professor. Computer Science. School of Computing")
    end

    it "leaves out the fields the directory has not filled" do
      faculty = create(:faculty, first_name: "Ada", last_name: "Lovelace", middle_name: nil, display_name: nil,
                                 title: nil, department: nil, school: nil)

      expect(faculty.embedding_text).to eq("Ada Lovelace")
    end
  end
end

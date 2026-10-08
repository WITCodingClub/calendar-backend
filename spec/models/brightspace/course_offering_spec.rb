# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: brightspace_course_offerings
#
#  id             :bigint           not null, primary key
#  data_version   :integer          default(1), not null
#  reported_total :jsonb
#  sections       :jsonb            not null
#  title          :string           not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  connection_id  :bigint           not null
#  course_id      :bigint
#  source_id      :string           not null
#  term_id        :bigint
#
# Indexes
#
#  idx_on_connection_id_source_id_cec08f631c            (connection_id,source_id) UNIQUE
#  index_brightspace_course_offerings_on_connection_id  (connection_id)
#  index_brightspace_course_offerings_on_course_id      (course_id)
#  index_brightspace_course_offerings_on_term_id        (term_id)
#
# Foreign Keys
#
#  fk_rails_...  (connection_id => brightspace_connections.id)
#  fk_rails_...  (course_id => courses.id)
#  fk_rails_...  (term_id => terms.id)
#
RSpec.describe Brightspace::CourseOffering, type: :model do
  subject { create(:brightspace_course_offering) }

  it { is_expected.to belong_to(:connection) }
  it { is_expected.to belong_to(:course).optional }
  it { is_expected.to belong_to(:term).optional }
  it { is_expected.to have_one(:user).through(:connection) }
  it { is_expected.to have_many(:assignments).dependent(:destroy) }
  it { is_expected.to have_many(:announcements).dependent(:destroy) }
  it { is_expected.to have_many(:grade_categories).dependent(:destroy) }
  it { is_expected.to have_many(:grade_items).dependent(:destroy) }
  it { is_expected.to have_one(:syllabus).dependent(:destroy) }

  it { is_expected.to validate_presence_of(:source_id) }
  it { is_expected.to validate_length_of(:source_id).is_at_most(64) }
  it { is_expected.to validate_uniqueness_of(:source_id).scoped_to(:connection_id).ignoring_case_sensitivity }
  it { is_expected.to validate_presence_of(:title) }
  it { is_expected.to validate_length_of(:title).is_at_most(500) }
  it { is_expected.to validate_numericality_of(:data_version).only_integer.is_greater_than(0) }

  describe "#bump_version!" do
    it "changes the version token" do
      offering = create(:brightspace_course_offering)

      expect { offering.bump_version! }.to change(offering, :version)
    end
  end

  describe ".for_user" do
    it "returns only the user's classes" do
      mine = create(:brightspace_course_offering)
      create(:brightspace_course_offering)

      expect(described_class.for_user(mine.connection.user)).to contain_exactly(mine)
    end
  end
end

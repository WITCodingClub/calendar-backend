# frozen_string_literal: true

require "rails_helper"

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
end

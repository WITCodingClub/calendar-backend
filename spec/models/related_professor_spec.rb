# frozen_string_literal: true

require "rails_helper"

RSpec.describe RelatedProfessor, type: :model do
  subject { create(:related_professor) }

  it { is_expected.to belong_to(:faculty) }
  it { is_expected.to belong_to(:related_faculty).class_name("Faculty").optional }

  it { is_expected.to validate_presence_of(:rmp_id) }
  it { is_expected.to validate_uniqueness_of(:rmp_id).scoped_to(:faculty_id) }
end

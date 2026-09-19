# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: related_professors
#
#  id                 :bigint           not null, primary key
#  avg_rating         :decimal(3, 2)
#  first_name         :string
#  last_name          :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  faculty_id         :bigint           not null
#  related_faculty_id :bigint
#  rmp_id             :string           not null
#
# Indexes
#
#  index_related_professors_on_faculty_id             (faculty_id)
#  index_related_professors_on_faculty_id_and_rmp_id  (faculty_id,rmp_id) UNIQUE
#  index_related_professors_on_related_faculty_id     (related_faculty_id)
#
# Foreign Keys
#
#  fk_rails_...  (faculty_id => faculties.id)
#  fk_rails_...  (related_faculty_id => faculties.id)
#
RSpec.describe RelatedProfessor, type: :model do
  subject { create(:related_professor) }

  it { is_expected.to belong_to(:faculty) }
  it { is_expected.to belong_to(:related_faculty).class_name("Faculty").optional }

  it { is_expected.to validate_presence_of(:rmp_id) }
  it { is_expected.to validate_uniqueness_of(:rmp_id).scoped_to(:faculty_id) }
end

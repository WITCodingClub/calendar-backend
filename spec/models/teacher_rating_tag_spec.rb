# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: teacher_rating_tags
#
#  id            :bigint           not null, primary key
#  tag_count     :integer          default(0)
#  tag_name      :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  faculty_id    :bigint           not null
#  rmp_legacy_id :integer          not null
#
# Indexes
#
#  index_teacher_rating_tags_on_faculty_id                    (faculty_id)
#  index_teacher_rating_tags_on_faculty_id_and_rmp_legacy_id  (faculty_id,rmp_legacy_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (faculty_id => faculties.id)
#
RSpec.describe TeacherRatingTag, type: :model do
  subject { create(:teacher_rating_tag) }

  it { is_expected.to belong_to(:faculty) }

  it { is_expected.to validate_presence_of(:rmp_legacy_id) }
  it { is_expected.to validate_uniqueness_of(:rmp_legacy_id).scoped_to(:faculty_id) }
  it { is_expected.to validate_presence_of(:tag_name) }
  it { is_expected.to validate_numericality_of(:tag_count).is_greater_than_or_equal_to(0) }
end

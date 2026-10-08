# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: brightspace_announcements
#
#  id                 :bigint           not null, primary key
#  body               :text
#  posted_at          :datetime
#  removed_at         :datetime
#  source_url         :string
#  title              :string           not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  course_offering_id :bigint           not null
#  source_id          :string           not null
#
# Indexes
#
#  index_brightspace_announcements_on_course_offering_id  (course_offering_id)
#  index_brightspace_announcements_on_source              (course_offering_id,source_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (course_offering_id => brightspace_course_offerings.id)
#
RSpec.describe Brightspace::Announcement, type: :model do
  subject { create(:brightspace_announcement) }

  it { is_expected.to belong_to(:course_offering) }
  it { is_expected.to validate_presence_of(:source_id) }
  it { is_expected.to validate_length_of(:source_id).is_at_most(64) }
  it { is_expected.to validate_uniqueness_of(:source_id).scoped_to(:course_offering_id).ignoring_case_sensitivity }
  it { is_expected.to validate_presence_of(:title) }
  it { is_expected.to validate_length_of(:title).is_at_most(500) }
end

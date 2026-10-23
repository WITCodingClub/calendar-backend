# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: academic_profiles
#
#  id                         :bigint           not null, primary key
#  admit_term_uid             :integer
#  admit_type                 :string
#  class_standing             :string
#  leopardweb_profile_digest  :string
#  leopardweb_programs_digest :string
#  leopardweb_synced_at       :datetime
#  level                      :string
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  user_id                    :bigint           not null
#
# Indexes
#
#  index_academic_profiles_on_user_id  (user_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
RSpec.describe AcademicProfile, type: :model do
  it { is_expected.to belong_to(:user) }

  # No matcher covers a unique index with no validation.
  it "allows one profile for each user" do
    profile = create(:academic_profile)

    expect { create(:academic_profile, user: profile.user) }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end

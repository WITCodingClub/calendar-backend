# frozen_string_literal: true

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
# What the LeopardWeb Student Profile page says about a student, as the
# extension sends it (#529). The programs are StudentProgram rows.
#
# The two digests are hashes of the profile fields and of the program list
# that the extension last read from LeopardWeb. AcademicProfiles::Sync skips
# each part when its digest is the same, so a value the student changed stays
# until LeopardWeb changes that part.
#
# A user has one row. The unique index enforces it, with no model validation,
# so AcademicProfiles::Sync can use create_or_find_by! when two requests race.
class AcademicProfile < ApplicationRecord
  belongs_to :user
end

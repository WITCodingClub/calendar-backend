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
FactoryBot.define do
  factory :academic_profile do
    user
    level { "Undergraduate" }
    class_standing { %w[Freshman Sophomore Junior Senior].sample }
    admit_type { "Freshman Admit (Domestic)" }
    admit_term_uid { 202610 }
  end
end

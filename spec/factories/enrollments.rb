# == Schema Information
#
# Table name: enrollments
# Database name: primary
#
#  id                :bigint           not null, primary key
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  academic_class_id :bigint           not null
#  term_id           :bigint           not null
#  user_id           :bigint           not null
#
# Indexes
#
#  index_enrollments_on_academic_class_id  (academic_class_id)
#  index_enrollments_on_term_id            (term_id)
#  index_enrollments_on_user_class_term    (user_id,academic_class_id,term_id) UNIQUE
#  index_enrollments_on_user_id            (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (academic_class_id => courses.id)
#  fk_rails_...  (term_id => terms.id)
#  fk_rails_...  (user_id => users.id)
#
FactoryBot.define do
  factory :enrollment do
    user { nil }
    academic_class { nil }
    term { nil }
  end
end

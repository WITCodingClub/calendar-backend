# frozen_string_literal: true

# == Schema Information
#
# Table name: course_prerequisites
# Database name: primary
#
#  id                 :bigint           not null, primary key
#  min_grade          :string
#  prerequisite_logic :string
#  prerequisite_rule  :text             not null
#  prerequisite_type  :string           not null
#  waivable           :boolean          default(FALSE), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  course_id          :bigint           not null
#
# Indexes
#
#  index_course_prerequisites_on_course_id                        (course_id)
#  index_course_prerequisites_on_course_id_and_prerequisite_type  (course_id,prerequisite_type)
#  index_course_prerequisites_on_prerequisite_type                (prerequisite_type)
#
# Foreign Keys
#
#  fk_rails_...  (course_id => courses.id)
#
FactoryBot.define do
  factory :course_prerequisite do
    course
    prerequisite_type { "prerequisite" }
    prerequisite_rule { "COMP1000" }
    prerequisite_logic { "and" }
    min_grade { "C" }
    waivable { false }

    trait :corequisite do
      prerequisite_type { "corequisite" }
      prerequisite_rule { "COMP2000 or MATH2300" }
    end

    trait :recommended do
      prerequisite_type { "recommended" }
      waivable { true }
    end

    trait :complex_logic do
      prerequisite_rule { "(COMP1000 and MATH2300) or (COMP1050 and MATH1777)" }
      prerequisite_logic { "complex" }
    end

    trait :waivable do
      waivable { true }
    end
  end
end

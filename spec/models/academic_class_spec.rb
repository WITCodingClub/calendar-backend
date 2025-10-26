# == Schema Information
#
# Table name: academic_classes
#
#  id             :bigint           not null, primary key
#  course_number  :integer
#  credit_hours   :integer
#  crn            :integer
#  grade_mode     :string
#  schedule_type  :string           not null
#  section_number :string           not null
#  subject        :string
#  title          :string
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  term_id        :bigint           not null
#
# Indexes
#
#  index_academic_classes_on_crn      (crn) UNIQUE
#  index_academic_classes_on_term_id  (term_id)
#
# Foreign Keys
#
#  fk_rails_...  (term_id => terms.id)
#
require 'rails_helper'

RSpec.describe AcademicClass, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end

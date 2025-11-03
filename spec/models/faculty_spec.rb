# == Schema Information
#
# Table name: faculties
# Database name: primary
#
#  id         :bigint           not null, primary key
#  email      :string           not null
#  first_name :string           not null
#  last_name  :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  rmp_id     :string
#
# Indexes
#
#  index_faculties_on_email   (email) UNIQUE
#  index_faculties_on_rmp_id  (rmp_id) UNIQUE
#
require 'rails_helper'

RSpec.describe Faculty, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end

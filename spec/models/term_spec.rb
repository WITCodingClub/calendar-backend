# == Schema Information
#
# Table name: terms
#
#  id         :bigint           not null, primary key
#  semester   :integer          not null
#  uid        :string           not null
#  year       :integer          not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_terms_on_uid                (uid) UNIQUE
#  index_terms_on_year_and_semester  (year,semester) UNIQUE
#
require 'rails_helper'

RSpec.describe Term, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end

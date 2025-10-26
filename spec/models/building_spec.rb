# == Schema Information
#
# Table name: buildings
#
#  id           :bigint           not null, primary key
#  abbreviation :string           not null
#  name         :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#
require 'rails_helper'

RSpec.describe Building, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end

# == Schema Information
#
# Table name: users
# Database name: primary
#
#  id           :bigint           not null, primary key
#  access_level :integer          default("user"), not null
#  email        :string           default(""), not null
#  first_name   :string
#  last_name    :string
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#
# Indexes
#
#  index_users_on_email  (email) UNIQUE
#
require 'rails_helper'

RSpec.describe User, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end

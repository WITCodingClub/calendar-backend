# frozen_string_literal: true

# == Schema Information
#
# Table name: buildings
# Database name: primary
#
#  id           :bigint           not null, primary key
#  abbreviation :string           not null
#  name         :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#
# Indexes
#
#  index_buildings_on_abbreviation  (abbreviation) UNIQUE
#  index_buildings_on_name          (name) UNIQUE
#
require "rails_helper"

RSpec.describe Building do
  pending "add some examples to (or delete) #{__FILE__}"
end

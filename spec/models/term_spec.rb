# frozen_string_literal: true

# == Schema Information
#
# Table name: terms
# Database name: primary
#
#  id         :bigint           not null, primary key
#  season     :integer
#  uid        :integer          not null
#  year       :integer
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_terms_on_uid              (uid) UNIQUE
#  index_terms_on_year_and_season  (year,season) UNIQUE
#
require "rails_helper"

RSpec.describe Term do
  pending "add some examples to (or delete) #{__FILE__}"
end

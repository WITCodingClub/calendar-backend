# frozen_string_literal: true

# == Schema Information
#
# Table name: rating_distributions
# Database name: primary
#
#  id                       :bigint           not null, primary key
#  avg_difficulty           :decimal(3, 2)
#  avg_rating               :decimal(3, 2)
#  num_ratings              :integer          default(0)
#  r1                       :integer          default(0)
#  r2                       :integer          default(0)
#  r3                       :integer          default(0)
#  r4                       :integer          default(0)
#  r5                       :integer          default(0)
#  total                    :integer          default(0)
#  would_take_again_percent :decimal(5, 2)
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  faculty_id               :bigint           not null
#
# Indexes
#
#  index_rating_distributions_on_faculty_id  (faculty_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (faculty_id => faculties.id)
#
require "rails_helper"

RSpec.describe RatingDistribution do
  pending "add some examples to (or delete) #{__FILE__}"
end

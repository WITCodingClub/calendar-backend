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
class RatingDistribution < ApplicationRecord
  belongs_to :faculty

  validates :faculty_id, uniqueness: true

  # Get percentage for each rating level
  def percentage(level)
    return 0 if total.zero?
    ((send("r#{level}").to_f / total) * 100).round(2)
  end

  # Get all percentages as a hash
  def percentages
    {
      r1: percentage(1),
      r2: percentage(2),
      r3: percentage(3),
      r4: percentage(4),
      r5: percentage(5)
    }
  end
end

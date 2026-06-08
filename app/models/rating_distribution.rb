# frozen_string_literal: true

class RatingDistribution < ApplicationRecord
  include EncodedIds::HashidIdentifiable

  set_public_id_prefix :rdi

  belongs_to :faculty

  validates :faculty_id, uniqueness: true

  def percentage(level)
    return 0 if total.zero?

    ((send("r#{level}").to_f / total) * 100).round(2)
  end

  def percentages
    (1..5).to_h { |i| [ "r#{i}".to_sym, percentage(i) ] }
  end
end

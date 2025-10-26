class Term < ApplicationRecord
  before_create :check_term_validity
  has_many :academic_classes, dependent: :destroy

  enum :semester, {
    spring: 1,
    fall: 2,
    summer: 3
  }

  def name
    "#{semester.to_s.capitalize} #{year}"
  end

  private

  def check_term_validity
    unless [ 1, 2, 3 ].include?(semester)
      errors.add(:semester, "must be 1 (Spring), 2 (Fall), or 3 (Summer)")
    end
  end

end

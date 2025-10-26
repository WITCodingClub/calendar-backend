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
class Term < ApplicationRecord
  before_create :check_term_validity
  validate :uniqueness_of_year_and_semester
  validate :term_validity
  has_many :academic_classes, dependent: :destroy
  has_many :enrollments, dependent: :destroy

  validates :uid, presence: true, uniqueness: true

  enum :semester, {
    spring: 1,
    fall: 2,
    summer: 3
  }

  def name
    "#{semester.to_s.capitalize} #{year}"
  end

  private

  def uniqueness_of_year_and_semester
    if Term.exists?(year: year, semester: semester)
      errors.add(:base, "Term with year #{year} and semester #{semester} already exists")
    end
  end

  def term_validity
    unless [ 1, 2, 3 ].include?(semester)
      errors.add(:semester, "must be 1 (Spring), 2 (Fall), or 3 (Summer)")
    end
  end


end

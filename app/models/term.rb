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
class Term < ApplicationRecord
  has_many :courses, dependent: :destroy
  has_many :enrollments, dependent: :destroy

  validates :uid, presence: true, uniqueness: true

  enum :season, {
    spring: 1,
    fall: 2,
    summer: 3
  }

  def name
    "#{season.to_s.capitalize} #{year}"
  end

  private

  def uniqueness_of_year_and_semester
    if Term.exists?(year: year, semester: semester)
      errors.add(:base, "Term with year #{year} and semester #{semester} already exists")
    end
  end


end

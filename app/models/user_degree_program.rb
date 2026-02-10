# frozen_string_literal: true

# == Schema Information
#
# Table name: user_degree_programs
# Database name: primary
#
#  id                    :bigint           not null, primary key
#  catalog_year          :integer          not null
#  completion_date       :date
#  declared_at           :datetime
#  primary               :boolean          default(FALSE), not null
#  program_type          :string           not null
#  status                :string           default("active"), not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  degree_program_id     :bigint           not null
#  leopardweb_program_id :string
#  user_id               :bigint           not null
#
# Indexes
#
#  index_user_degree_programs_on_degree_program_id              (degree_program_id)
#  index_user_degree_programs_on_status                         (status)
#  index_user_degree_programs_on_user_id                        (user_id)
#  index_user_degree_programs_on_user_id_and_degree_program_id  (user_id,degree_program_id) UNIQUE
#  index_user_degree_programs_on_user_id_and_primary            (user_id,primary) UNIQUE WHERE ("primary" = true)
#
# Foreign Keys
#
#  fk_rails_...  (degree_program_id => degree_programs.id)
#  fk_rails_...  (user_id => users.id)
#
class UserDegreeProgram < ApplicationRecord
  belongs_to :user
  belongs_to :degree_program

  validates :program_type, presence: true
  validates :catalog_year, presence: true, numericality: { only_integer: true, greater_than: 2000 }
  validates :status, presence: true
  validates :degree_program_id, uniqueness: { scope: :user_id }
  validate :only_one_primary_per_user

  enum :status, {
    active: "active",
    completed: "completed",
    dropped: "dropped",
    suspended: "suspended"
  }, default: :active

  enum :program_type, {
    major: "major",
    minor: "minor",
    certificate: "certificate",
    concentration: "concentration"
  }

  scope :active, -> { where(status: :active) }
  scope :primary, -> { where(primary: true) }
  scope :by_type, ->(type) { where(program_type: type) }

  private

  def only_one_primary_per_user
    return unless primary?

    existing = UserDegreeProgram.where(user_id: user_id, primary: true).where.not(id: id)
    errors.add(:primary, "user can only have one primary degree program") if existing.exists?
  end

end

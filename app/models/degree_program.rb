# frozen_string_literal: true

# == Schema Information
#
# Table name: degree_programs
# Database name: primary
#
#  id                    :bigint           not null, primary key
#  active                :boolean          default(TRUE), not null
#  catalog_year          :integer          not null
#  college               :string
#  credit_hours_required :decimal(5, 2)
#  degree_type           :string           not null
#  department            :string
#  leopardweb_code       :string           not null
#  level                 :string           not null
#  minimum_gpa           :decimal(3, 2)
#  program_code          :string           not null
#  program_name          :string           not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#
# Indexes
#
#  index_degree_programs_on_active                         (active)
#  index_degree_programs_on_catalog_year_and_program_code  (catalog_year,program_code)
#  index_degree_programs_on_leopardweb_code                (leopardweb_code) UNIQUE
#  index_degree_programs_on_program_code                   (program_code) UNIQUE
#
class DegreeProgram < ApplicationRecord
  include EncodedIds::HashidIdentifiable

  set_public_id_prefix :dgp

  has_many :user_degree_programs, dependent: :destroy
  has_many :users, through: :user_degree_programs
  has_many :degree_requirements, dependent: :destroy
  has_many :degree_evaluation_snapshots, dependent: :destroy

  validates :program_code, presence: true, uniqueness: true
  validates :leopardweb_code, presence: true, uniqueness: true
  validates :program_name, presence: true
  validates :degree_type, presence: true
  validates :level, presence: true
  validates :catalog_year, presence: true, numericality: { only_integer: true, greater_than: 2000 }
  validates :credit_hours_required, numericality: { greater_than: 0 }, allow_nil: true
  validates :minimum_gpa, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 4.0 }, allow_nil: true

  scope :active, -> { where(active: true) }
  scope :by_catalog_year, ->(year) { where(catalog_year: year) }
  scope :by_level, ->(level) { where(level: level) }

end

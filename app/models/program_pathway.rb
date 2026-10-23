# frozen_string_literal: true

# A path through more than one program, such as a 3+1 or 4+1 master's
# degree (Double Leopard) or the 5-year B.S. plus M.Arch. The steps name the
# programs in order.
#
# max_shared_courses and max_shared_credits are how much of one program can
# also count toward the next: Double Leopard students take up to two
# graduate courses in their senior year.
# == Schema Information
#
# Table name: program_pathways
#
#  id                 :bigint           not null, primary key
#  active             :boolean          default(TRUE), not null
#  kind               :string           not null
#  max_shared_courses :integer
#  max_shared_credits :integer
#  name               :string           not null
#  slug               :string           not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#
# Indexes
#
#  index_program_pathways_on_slug  (slug) UNIQUE
#
class ProgramPathway < ApplicationRecord
  KINDS = { three_plus_one: "three_plus_one", four_plus_one: "four_plus_one", five_year: "five_year" }.freeze

  enum :kind, KINDS, validate: true

  has_many :steps, -> { order(:position) }, class_name: "ProgramPathwayStep", dependent: :delete_all,
                                             inverse_of: :program_pathway
  has_many :degree_programs, through: :steps

  scope :active, -> { where(active: true) }

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :max_shared_courses, :max_shared_credits,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
end

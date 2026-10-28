# frozen_string_literal: true

# One elective list PDF that a school publishes for a term, such as
# "Spring 2027 School of Computing and Data Science Electives". body_text is
# the text of the PDF. It keeps the rules that name no course, such as "Any
# 2000-Level courses in BIOE, BIOL, ...". sha256 is the digest of the PDF,
# so the import skips a file that did not change.
# == Schema Information
#
# Table name: term_elective_lists
#
#  id         :bigint           not null, primary key
#  body_text  :text
#  fetched_at :datetime         not null
#  school     :string
#  sha256     :string           not null
#  title      :string
#  url        :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  term_id    :bigint           not null
#
# Indexes
#
#  index_term_elective_lists_on_term_id  (term_id)
#  index_term_elective_lists_on_url      (url) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (term_id => terms.id) ON DELETE => cascade
#
class TermElectiveList < ApplicationRecord
  belongs_to :term

  has_many :courses, -> { order(:position) }, class_name: "TermElectiveCourse", dependent: :delete_all,
                                               inverse_of: :term_elective_list

  validates :url, presence: true, uniqueness: true
  validates :sha256, :fetched_at, presence: true
end

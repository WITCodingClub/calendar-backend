# frozen_string_literal: true

# == Schema Information
#
# Table name: related_professors
# Database name: primary
#
#  id                 :bigint           not null, primary key
#  avg_rating         :decimal(3, 2)
#  first_name         :string
#  last_name          :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  faculty_id         :bigint           not null
#  related_faculty_id :bigint
#  rmp_id             :string           not null
#
# Indexes
#
#  index_related_professors_on_faculty_id_and_rmp_id  (faculty_id,rmp_id) UNIQUE
#  index_related_professors_on_related_faculty_id     (related_faculty_id)
#
# Foreign Keys
#
#  fk_rails_...  (faculty_id => faculties.id)
#  fk_rails_...  (related_faculty_id => faculties.id)
#
class RelatedProfessor < ApplicationRecord
  include EncodedIds::HashidIdentifiable

  set_public_id_prefix :rpr

  belongs_to :faculty
  belongs_to :related_faculty, class_name: "Faculty", optional: true

  validates :rmp_id, presence: true, uniqueness: { scope: :faculty_id }

  # Attempt to match this related professor to an existing faculty record
  def try_match_faculty!
    return if related_faculty.present?

    matched = Faculty.find_by(rmp_id: rmp_id)
    update(related_faculty: matched) if matched
  end

  def full_name
    "#{first_name} #{last_name}"
  end

end

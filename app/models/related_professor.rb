# frozen_string_literal: true

class RelatedProfessor < ApplicationRecord
  include EncodedIds::HashidIdentifiable

  set_public_id_prefix :rpr

  belongs_to :faculty
  belongs_to :related_faculty, class_name: "Faculty", optional: true

  validates :rmp_id, presence: true, uniqueness: { scope: :faculty_id }

  def try_match_faculty!
    return if related_faculty.present?

    matched = Faculty.find_by(rmp_id: rmp_id)
    update(related_faculty: matched) if matched
  end

  def full_name
    "#{first_name} #{last_name}"
  end
end

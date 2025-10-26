# == Schema Information
#
# Table name: faculties
#
#  id         :bigint           not null, primary key
#  email      :string           not null
#  first_name :string           not null
#  last_name  :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_faculties_on_email  (email) UNIQUE
#
class Faculty < ApplicationRecord
  has_and_belongs_to_many :academic_classes

  def full_name
    "#{first_name} #{last_name}"
  end

  def initials
    "#{first_name[0]}#{last_name[0]}"
  end

  def u_name
    def fwd
      "#{first_name[0]}. #{last_name}"
    end

    def rev
      "#{last_name}, #{first_name[0]}."
    end
  end



end

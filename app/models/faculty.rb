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

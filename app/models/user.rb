class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  before_create :check_access_level

  private

  def full_name
    "#{first_name} #{last_name}"
  end

  def check_access_level
    unless [0, 1, 2].include?(access_level)
      errors.add(:access_level, "must be 0 (Student), 1 (Admin), or 2 (Owner)")
    end
  end

end

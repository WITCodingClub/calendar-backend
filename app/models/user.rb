# == Schema Information
#
# Table name: users
#
#  id           :bigint           not null, primary key
#  access_level :integer          default("user"), not null
#  email        :string           default(""), not null
#  first_name   :string
#  last_name    :string
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#
# Indexes
#
#  index_users_on_email  (email) UNIQUE
#
class User < ApplicationRecord
  has_subscriptions

  has_many :enrollments, dependent: :destroy
  has_many :academic_classes, through: :enrollments
  has_many :magic_links, dependent: :destroy

  enum :access_level, {
    user: 0,
    admin: 1,
    super_admin: 2,
    owner: 3
  }, default: :user, null: false

  def admin_access?
    admin? || super_admin? || owner?
  end

  def full_name
    # first_name then last_name or John Doe if no name
    "#{first_name} #{last_name}"
  end

end

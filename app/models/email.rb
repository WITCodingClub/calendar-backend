# == Schema Information
#
# Table name: emails
# Database name: primary
#
#  id         :bigint           not null, primary key
#  email      :string           not null
#  g_cal      :boolean          default(FALSE), not null
#  primary    :boolean          default(FALSE)
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_emails_on_user_id              (user_id)
#  index_emails_on_user_id_and_primary  (user_id,primary) UNIQUE WHERE ("primary" = true)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class Email < ApplicationRecord
  belongs_to :user

  validates :email, presence: true, uniqueness: true, format: {
    with: /\A[^@\s]+@[^@\s]+\z/,
    message: "must be a valid email address"
  }
  validate :has_one_primary_email

  def is_wit_email?
    email.match?(/@wit\.edu\z/i)
  end

  private

  def has_one_primary_email
    if primary
      existing_primary = Email.where(user_id: user_id, primary: true).where.not(id: id)
      if existing_primary.exists?
        errors.add(:primary, "There can only be one primary email.")
      end
    end
  end

end

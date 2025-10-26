# == Schema Information
#
# Table name: ahoy_messages
#
#  id            :bigint           not null, primary key
#  campaign      :string
#  mailer        :string
#  sent_at       :datetime
#  subject       :text
#  to_bidx       :string
#  to_ciphertext :text
#  user_type     :string
#  user_id       :bigint
#
# Indexes
#
#  index_ahoy_messages_on_campaign  (campaign)
#  index_ahoy_messages_on_to_bidx   (to_bidx)
#  index_ahoy_messages_on_user      (user_type,user_id)
#
class Ahoy::Message < ActiveRecord::Base
  self.table_name = "ahoy_messages"

  belongs_to :user, polymorphic: true, optional: true

  has_encrypted :to
  blind_index :to
end

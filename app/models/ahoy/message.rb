# frozen_string_literal: true

# == Schema Information
#
# Table name: ahoy_messages
# Database name: primary
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
module Ahoy
  class Message < ApplicationRecord
    self.table_name = "ahoy_messages"

    include EncodedIds::HashidIdentifiable

    belongs_to :user, polymorphic: true, optional: true

    has_encrypted :to
    blind_index :to

  end
end

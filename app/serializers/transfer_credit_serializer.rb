# frozen_string_literal: true

# == Schema Information
#
# Table name: transfer_credits
#
#  id         :bigint           not null, primary key
#  code       :string           not null
#  credits    :integer
#  kind       :string
#  source     :string           not null
#  title      :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_transfer_credits_on_user_id_and_code  (user_id,code) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
# One TransferCredit, for /api/user/transfer_credits (#1020).
class TransferCreditSerializer
  def initialize(credit)
    @credit = credit
  end

  def as_json(*)
    {
      code:       @credit.code,
      title:      @credit.title,
      credits:    @credit.credits,
      source:     @credit.source,
      kind:       @credit.kind,
      # A student entry can be removed. A transcript entry cannot.
      removable:  @credit.student?,
      updated_at: @credit.updated_at&.iso8601
    }
  end
end

# frozen_string_literal: true

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
#  index_emails_on_email                (email) UNIQUE
#  index_emails_on_user_id              (user_id)
#  index_emails_on_user_id_and_primary  (user_id,primary) UNIQUE WHERE ("primary" = true)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
require "rails_helper"

RSpec.describe Email do
  pending "add some examples to (or delete) #{__FILE__}"
end

# == Schema Information
#
# Table name: magic_links
# Database name: primary
#
#  id         :bigint           not null, primary key
#  expires_at :datetime         not null
#  token      :string           not null
#  used_at    :datetime
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_magic_links_on_token    (token) UNIQUE
#  index_magic_links_on_user_id  (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
FactoryBot.define do
  factory :magic_link do
    user { nil }
    token { "MyString" }
    expires_at { "2025-10-26 17:28:19" }
    used_at { "2025-10-26 17:28:19" }
  end
end

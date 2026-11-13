# frozen_string_literal: true

# == Schema Information
#
# Table name: registration_plans
#
#  id          :bigint           not null, primary key
#  courses     :jsonb            not null
#  preferences :jsonb            not null
#  term_uid    :integer          not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  user_id     :bigint           not null
#
# Indexes
#
#  index_registration_plans_on_term_uid              (term_uid)
#  index_registration_plans_on_user_id_and_term_uid  (user_id,term_uid) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (term_uid => terms.uid) ON DELETE => cascade
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
FactoryBot.define do
  factory :registration_plan do
    user
    term
    courses do
      [ { "code" => "WDGT #{Faker::Number.between(from: 1000, to: 4999)}",
          "crns" => [ Faker::Number.number(digits: 5).to_s ],
          "fills" => { "kind" => "course", "label" => Faker::Educator.subject } } ]
    end
    preferences { { "earliest" => "09:00", "open_only" => true } }
  end
end

# frozen_string_literal: true

# == Schema Information
#
# Table name: term_elective_lists
#
#  id         :bigint           not null, primary key
#  body_text  :text
#  fetched_at :datetime         not null
#  school     :string
#  sha256     :string           not null
#  title      :string
#  url        :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  term_id    :bigint           not null
#
# Indexes
#
#  index_term_elective_lists_on_term_id  (term_id)
#  index_term_elective_lists_on_url      (url) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (term_id => terms.id) ON DELETE => cascade
#
FactoryBot.define do
  factory :term_elective_list do
    term
    sequence(:url) { |n| "https://wit.edu/sites/default/files/2026-10/SCDS_Electives_#{n}.pdf" }
    school { "SCDS" }
    title { Faker::Educator.subject }
    sha256 { Digest::SHA256.hexdigest(url) }
    fetched_at { Time.current }
  end
end

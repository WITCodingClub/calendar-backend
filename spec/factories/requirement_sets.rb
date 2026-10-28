# frozen_string_literal: true

# == Schema Information
#
# Table name: requirement_sets
#
#  id                :bigint           not null, primary key
#  department_name   :string
#  description       :text
#  fetched_at        :datetime
#  last_seen_at      :datetime
#  name              :string           not null
#  needs_review      :boolean          default(FALSE), not null
#  path              :string
#  school_name       :string
#  source            :string           default("html"), not null
#  source_digest     :string
#  total_credits     :integer
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  catalog_year_id   :bigint           not null
#  degree_program_id :bigint           not null
#
# Indexes
#
#  idx_on_degree_program_id_catalog_year_id_10cd4884bd  (degree_program_id,catalog_year_id) UNIQUE
#  index_requirement_sets_on_catalog_year_id            (catalog_year_id)
#
# Foreign Keys
#
#  fk_rails_...  (catalog_year_id => catalog_years.id)
#  fk_rails_...  (degree_program_id => degree_programs.id)
#
FactoryBot.define do
  factory :requirement_set do
    degree_program
    catalog_year
    name { degree_program.name }
    school_name { "School of #{Faker::Educator.subject}" }
    total_credits { 120 }
    last_seen_at { Time.current }

    # A program that the last import of its year did not find.
    trait :unlisted do
      last_seen_at { 1.year.ago }
    end

    trait :from_pdf do
      source { "pdf" }
      needs_review { true }
    end
  end
end

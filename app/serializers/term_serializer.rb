# frozen_string_literal: true

# == Schema Information
#
# Table name: terms
# Database name: primary
#
#  id                  :bigint           not null, primary key
#  catalog_imported    :boolean          default(FALSE), not null
#  catalog_imported_at :datetime
#  end_date            :date
#  season              :integer
#  start_date          :date
#  uid                 :integer          not null
#  year                :integer
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#
# Indexes
#
#  index_terms_on_uid              (uid) UNIQUE
#  index_terms_on_year_and_season  (year,season) UNIQUE
#
class TermSerializer
  def initialize(term)
    @term = term
  end

  def as_json(*)
    return nil if @term.nil?

    {
      name: @term.name,
      id: @term.uid,
      pub_id: @term.public_id,
      start_date: @term.start_date,
      end_date: @term.end_date
    }
  end

end

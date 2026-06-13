# frozen_string_literal: true

# == Schema Information
#
# Table name: terms
#
#  id                    :bigint           not null, primary key
#  catalog_import_failed :boolean          default(FALSE), not null
#  catalog_imported      :boolean          default(FALSE), not null
#  catalog_imported_at   :datetime
#  catalog_importing     :boolean          default(FALSE), not null
#  end_date              :date
#  season                :integer          not null
#  start_date            :date
#  uid                   :integer          not null
#  year                  :integer          not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  catalog_import_job_id :string
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
      name:       @term.name,
      id:         @term.uid,
      pub_id:     @term.public_id,
      start_date: @term.start_date,
      end_date:   @term.end_date
    }
  end
end

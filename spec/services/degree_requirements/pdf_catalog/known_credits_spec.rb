# frozen_string_literal: true

require "rails_helper"

RSpec.describe DegreeRequirements::PdfCatalog::KnownCredits do
  it "takes the credits of the nearest other catalog year, else the Banner credit hours" do
    near = create(:catalog_year, start_year: 2015)
    far = create(:catalog_year, start_year: 2019)
    own = create(:catalog_year, start_year: 2016)
    create(:catalog_year_course, catalog_year: far, subject_code: "MGMT", course_number: 2500, min_credits: 3, max_credits: 3)
    create(:catalog_year_course, catalog_year: near, subject_code: "MGMT", course_number: 2500, min_credits: 4, max_credits: 4)
    # The year itself and a credit range are not used.
    create(:catalog_year_course, catalog_year: own, subject_code: "ELEC", course_number: 3150, min_credits: 2, max_credits: 2)
    create(:catalog_year_course, catalog_year: near, subject_code: "ARCH", course_number: 1000, min_credits: 3, max_credits: 4)
    create(:catalog_course, subject_code: "ELEC", course_number: 3150, credit_hours: 4)
    create(:catalog_course, subject_code: "MGMT", course_number: 2500, credit_hours: 2)

    expect(described_class.call(2016)).to eq({ [ "MGMT", 2500 ] => 4, [ "ELEC", 3150 ] => 4 })
  end
end

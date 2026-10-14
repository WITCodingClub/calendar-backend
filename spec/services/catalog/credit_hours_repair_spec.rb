# frozen_string_literal: true

require "rails_helper"

RSpec.describe Catalog::CreditHoursRepair do
  let(:term) { create(:term) }

  it "sets each section to the import rule and counts the changes" do
    lecture = create(:course, term: term, crn: 21168, credit_hours: 4)
    lab     = create(:course, term: term, crn: 21269, credit_hours: 4)
    allow(Catalog::LeopardWebClient).to receive(:get_course_catalog).with(term: term.uid).and_return(
      success: true,
      courses: [
        { "courseReferenceNumber" => "21168", "creditHours" => 4 },
        { "courseReferenceNumber" => "21269", "creditHours" => 0 },
        { "courseReferenceNumber" => "29999", "creditHours" => 4 }
      ]
    )

    expect(described_class.call(term)).to eq(checked: 3, changed: 1)
    expect(lecture.reload.credit_hours).to eq(4)
    expect(lab.reload.credit_hours).to be_nil
  end

  it "raises when the catalog fetch fails" do
    allow(Catalog::LeopardWebClient).to receive(:get_course_catalog).and_return(success: false, error: "timeout")

    expect { described_class.call(term) }.to raise_error(Catalog::LeopardWebClient::RequestError, /timeout/)
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe Catalog::SectionLinksSync do
  let(:term)    { create(:term, uid: 202720, season: :spring, year: 2027) }
  let(:lecture) { create(:course, term: term, crn: 20452, course_number: 4960, schedule_type: "LEC", is_section_linked: true, link_identifier: "A2") }
  let(:lab)     { create(:course, term: term, crn: 20455, course_number: 4960, schedule_type: "LAB", is_section_linked: true, link_identifier: "B1") }
  let(:url)     { "#{Catalog::LeopardWebClient::BASE_URL}fetchLinkedSections" }

  def stub_links(crn, fixture, status: 200)
    stub_request(:get, url).with(query: { term: "202720", courseReferenceNumber: crn.to_s })
                           .to_return(status: status, body: file_fixture("leopard_web/#{fixture}").read,
                                      headers: { "Content-Type" => "application/json" })
  end

  it "stores Banner's pair with Banner's credits for the partner" do
    lab
    stub_links(20452, "linked_sections_lecture.json")

    expect(described_class.call(lecture)).to be(true)

    expect(lecture.section_links.pluck(:linked_course_id, :option_group, :credit_hours)).to eq([ [ lab.id, 0, 0 ] ])
    expect(lecture.reload.links_fetched_at).to be_present
  end

  it "keeps each option group" do
    lab
    other_lab  = create(:course, term: term, crn: 20456, course_number: 4960, schedule_type: "LAB")
    recitation = create(:course, term: term, crn: 20459, course_number: 4960, schedule_type: "LEC")
    stub_links(20452, "linked_sections_options.json")

    described_class.call(lecture)

    groups = lecture.section_links.order(:option_group, :linked_course_id).group_by(&:option_group)
    expect(groups.transform_values { |links| links.map(&:linked_course_id) })
      .to eq(0 => [ lab.id ], 1 => [ other_lab.id, recitation.id ].sort)
  end

  it "replaces the old links and skips a CRN that is not in the term" do
    create(:section_link, course: lecture, linked_course: create(:course, term: term), option_group: 0)
    stub_links(20452, "linked_sections_lecture.json")

    described_class.call(lecture)

    expect(lecture.section_links.count).to eq(0)
    expect(lecture.reload.links_fetched_at).to be_present
  end

  it "stores no partners when Banner gives none" do
    stub_links(20452, "linked_sections_none.json")

    described_class.call(lecture)

    expect(lecture.section_links).to be_empty
    expect(Catalog::SectionLinks.new(lecture.reload)).not_to be_required
  end

  it "keeps the old links and reports when Banner fails" do
    link = create(:section_link, course: lecture, linked_course: lab)
    stub_request(:get, url).with(query: hash_including(courseReferenceNumber: "20452")).to_return(status: 500, body: "error")

    reports = capture_error_reports { expect(described_class.call(lecture)).to be(false) }

    expect(reports.map { |r| r.error.class }).to eq([ Catalog::LeopardWebClient::RequestError ])
    expect(reports.first.context).to include(course_id: lecture.id, crn: 20452)
    expect(SectionLink.exists?(link.id)).to be(true)
    expect(lecture.reload.links_fetched_at).to be_nil
  end

  it "clears the links of a section that is no longer linked, with no request" do
    create(:section_link, course: lecture, linked_course: lab)
    lecture.update!(is_section_linked: false)

    expect(described_class.call(lecture)).to be(true)
    expect(lecture.section_links.count).to eq(0)
  end

  describe ".for_term" do
    it "fetches every linked section in the term and counts the results" do
      lecture
      lab
      create(:course, term: term, is_section_linked: false)
      stub_links(20452, "linked_sections_lecture.json")
      stub_links(20455, "linked_sections_lab.json", status: 500)

      reports = capture_error_reports do
        expect(described_class.for_term(term, pause: 0)).to eq(synced: 1, failed: 1)
      end

      expect(reports.size).to eq(1)
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe AdminMailer do
  describe "#missing_rmp_ids_summary" do
    # Issue #689: the course counts come from the preloaded courses, so two
    # rows do not run two count queries.
    it "lists each professor with a course count" do
      term = create(:term)
      one = create(:faculty, first_name: "Ada", last_name: "Lovelace")
      two = create(:faculty, first_name: "Grace", last_name: "Hopper")
      create(:course, term: term).faculties << one
      2.times { create(:course, term: term).faculties << two }

      body = Nokogiri::HTML(described_class.missing_rmp_ids_summary(email: "admin@wit.edu").body.decoded)
      rows = body.css("tbody tr").to_h { |tr| [ tr.css("td").first.text, tr.css("td").last.text ] }

      expect(rows).to eq("Ada Lovelace" => "1", "Grace Hopper" => "2")
    end
  end
end

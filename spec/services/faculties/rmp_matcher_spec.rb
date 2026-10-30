# frozen_string_literal: true

require "rails_helper"

RSpec.describe Faculties::RmpMatcher do
  let(:base_url) { Faculties::RateMyProfessorClient::BASE_URL }

  def teacher(first, last, id: "VGVhY2hlci0#{first}#{last}")
    { "id" => id, "firstName" => first, "lastName" => last }
  end

  def best_match(faculty, *nodes)
    described_class.new(faculty).best_match(nodes)
  end

  describe "#best_match" do
    it "matches a first name with one letter changed" do
      faculty = build(:faculty, first_name: "Ahmad", last_name: "Qorvin")
      node = teacher("Ahmed", "Qorvin")

      expect(best_match(faculty, node)).to eq(node)
    end

    it "matches a nickname, a short form, and a middle name" do
      expect(best_match(build(:faculty, first_name: "William", last_name: "Doe"), teacher("Bill", "Doe"))).to be_present
      expect(best_match(build(:faculty, first_name: "Christopher", last_name: "Doe"), teacher("Chris", "Doe"))).to be_present
      expect(best_match(build(:faculty, first_name: "Robert", middle_name: "Alan", last_name: "Doe"), teacher("Alan", "Doe"))).to be_present
    end

    it "matches one half of a hyphenated last name, and accents and case" do
      expect(best_match(build(:faculty, first_name: "Ana", last_name: "Garcia-Lopez"), teacher("Ana", "Garcia"))).to be_present
      expect(best_match(build(:faculty, first_name: "José", last_name: "Peña"), teacher("jose", "PENA"))).to be_present
    end

    it "does not match when both names differ" do
      faculty = build(:faculty, first_name: "Ahmad", last_name: "Qorvin")

      expect(best_match(faculty, teacher("Ahmed", "Qorvan"))).to be_nil
      expect(best_match(faculty, teacher("Brenda", "Qorvin"))).to be_nil
    end

    it "prefers the exact name over a close one" do
      faculty = build(:faculty, first_name: "Dana", last_name: "Hollis")
      exact = teacher("Dana", "Hollis")

      expect(best_match(faculty, teacher("Dena", "Hollis"), exact)).to eq(exact)
    end

    it "returns nil when two teachers match equally well" do
      faculty = build(:faculty, first_name: "Dana", last_name: "Hollis")

      expect(best_match(faculty, teacher("Dana", "Hollis", id: "a"), teacher("Dana", "Hollis", id: "b"))).to be_nil
    end

    it "skips a teacher another faculty member already has" do
      create(:faculty, rmp_id: "taken")
      faculty = create(:faculty, first_name: "Dana", last_name: "Hollis")

      expect(best_match(faculty, teacher("Dana", "Hollis", id: "taken"))).to be_nil
    end
  end

  describe "#candidates" do
    it "searches the full name and the last name, without duplicates" do
      faculty = build(:faculty, first_name: "Ahmad", last_name: "Qorvin")
      stub_request(:post, base_url)
        .with(body: hash_including("operationName" => "NewSearchTeachersQuery"))
        .to_return(status: 200, body: file_fixture("rate_my_professor/search_spelling_variant.json").read,
                   headers: { "Content-Type" => "application/json" })

      candidates = described_class.new(faculty).candidates

      expect(candidates.map { |node| node["lastName"] }).to eq([ "Qorvin" ])
      %w[Ahmad\ Qorvin Qorvin].each do |text|
        expect(WebMock).to have_requested(:post, base_url)
          .with(body: hash_including("variables" => hash_including("query" => hash_including("text" => text))))
      end
    end
  end
end

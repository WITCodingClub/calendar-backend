# frozen_string_literal: true

require "rails_helper"

RSpec.describe Faculties::RmpMatcher do
  let(:base_url) { Faculties::RateMyProfessorClient::BASE_URL }

  def teacher(first, last, id: "#{first}-#{last}")
    { "id" => id, "firstName" => first, "lastName" => last }
  end

  def faculty(first, last, **attributes)
    build(:faculty, first_name: first, last_name: last, **attributes)
  end

  def best_match(faculty, *nodes)
    described_class.new(faculty).best_match(nodes)
  end

  describe "#best_match" do
    it "matches a long first name with a changed vowel" do
      expect(best_match(faculty("Muhammad", "Qorvin"), teacher("Muhammed", "Qorvin"))).to be_present
      expect(best_match(faculty("Mohammad", "Qorvin"), teacher("Muhammed", "Qorvin"))).to be_present
    end

    it "matches a nickname and a middle name" do
      expect(best_match(faculty("William", "Doe"), teacher("Bill", "Doe"))).to be_present
      expect(best_match(faculty("Christopher", "Doe"), teacher("Chris", "Doe"))).to be_present
      expect(best_match(faculty("Robert", "Doe", middle_name: "Alan"), teacher("Alan", "Doe"))).to be_present
    end

    it "matches one half of a hyphenated last name, and accents and case" do
      expect(best_match(faculty("Ana", "Garcia-Lopez"), teacher("Ana", "Garcia"))).to be_present
      expect(best_match(faculty("José", "Peña"), teacher("jose", "PENA"))).to be_present
    end

    # Each pair is two different names, not two spellings of one name.
    it "does not match a different person with a similar name" do
      [
        [ %w[John Smith], %w[Joan Smith] ],
        [ %w[Mark Chen], %w[Mary Chen] ],
        [ %w[Eric Lopez], %w[Erica Lopez] ],
        [ %w[Daniel Ruiz], %w[Daniela Ruiz] ],
        [ %w[Antonio Ruiz], %w[Antonia Ruiz] ],
        [ %w[Andrew Ruiz], %w[Andrea Ruiz] ],
        [ %w[Chris Doe], %w[Christina Doe] ],
        [ %w[Mark Chen], %w[Mark Chan] ],
        [ %w[Wei Wang], %w[Wei Yang] ],
        [ [ "John", "Van Buren" ], [ "John", "Van Dyke" ] ],
        [ [ "Maria", "De La Cruz" ], [ "Maria", "De Souza" ] ]
      ].each do |(ours, theirs)|
        expect(best_match(faculty(*ours), teacher(*theirs))).to be_nil, "#{ours.join(' ')} matched #{theirs.join(' ')}"
      end
    end

    it "does not match when both names differ" do
      expect(best_match(faculty("Muhammad", "Qorvin"), teacher("Muhammed", "Qorvan"))).to be_nil
      expect(best_match(faculty("William", "Garcia-Lopez"), teacher("Bill", "Garcia"))).to be_nil
    end

    it "prefers the exact name over a close spelling" do
      exact = teacher("Muhammad", "Qorvin")

      expect(best_match(faculty("Muhammad", "Qorvin"), teacher("Muhammed", "Qorvin"), exact)).to eq(exact)
    end

    it "returns nil when two teachers have the exact name" do
      expect(best_match(faculty("Dana", "Hollis"), teacher("Dana", "Hollis", id: "a"), teacher("Dana", "Hollis", id: "b"))).to be_nil
    end

    it "returns nil when two close spellings qualify" do
      expect(best_match(faculty("Muhammad", "Qorvin"), teacher("Muhammed", "Qorvin"), teacher("Mohammad", "Qorvin"))).to be_nil
    end

    it "returns nil when the best teacher belongs to another faculty member, even with a weaker one left" do
      create(:faculty, rmp_id: "taken")
      ours = create(:faculty, first_name: "Muhammad", last_name: "Qorvin")

      expect(best_match(ours, teacher("Muhammad", "Qorvin", id: "taken"), teacher("Muhammed", "Qorvin"))).to be_nil
    end
  end

  describe "#candidates" do
    def stub_search(text, fixture)
      stub_request(:post, base_url)
        .with(body: hash_including("variables" => hash_including("query" => hash_including("text" => text))))
        .to_return(status: 200, body: file_fixture("rate_my_professor/#{fixture}").read,
                   headers: { "Content-Type" => "application/json" })
    end

    it "searches the full name and the last name, without duplicates" do
      stub_search("Ahmad Qorvin", "search_spelling_variant.json")
      stub_search("Qorvin", "search_spelling_variant.json")

      candidates = described_class.new(faculty("Ahmad", "Qorvin")).candidates

      expect(candidates.map { |node| node["id"] }).to eq([ "VGVhY2hlci03Nzc3Nzc=" ])
    end

    it "leaves out teachers at other schools" do
      stub_search("Ahmad Qorvin", "search_empty.json")
      stub_search("Qorvin", "search_other_school.json")

      expect(described_class.new(faculty("Ahmad", "Qorvin")).candidates).to be_empty
    end
  end
end

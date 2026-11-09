# frozen_string_literal: true

require "rails_helper"

RSpec.describe Catalog::SubjectLabels do
  let(:subjects_url) { %r{\Ahttps://selfservice\.wit\.edu/StudentRegistrationSsb/ssb/classSearch/get_subject} }

  def stub_subjects(status: 200)
    stub_request(:get, subjects_url).with(query: hash_including("term" => "202710"))
                                    .to_return(status: status, body: file_fixture("leopard_web/subjects.json").read,
                                               headers: { "Content-Type" => "application/json" })
  end

  describe ".label" do
    it "adds the code to a label without it" do
      expect(described_class.label("Climate Resilience", "CRES")).to eq("Climate Resilience (CRES)")
    end

    it "keeps a label that ends with the code" do
      expect(described_class.label("Computer Science (COMP)", "COMP")).to eq("Computer Science (COMP)")
    end

    it "adds the code after parentheses that are not a code" do
      expect(described_class.label("Graduate Internship (optional)", "INTN")).to eq("Graduate Internship (optional) (INTN)")
    end

    it "replaces a different code at the end of the label" do
      expect(described_class.label("Facilities Management (CPCE)", "CPFM")).to eq("Facilities Management (CPFM)")
    end

    it "gives the code when there is no description" do
      expect(described_class.label(nil, "COMP")).to eq("COMP")
    end
  end

  describe ".for_term" do
    it "adds the code from Banner's subject list for the term" do
      stub_subjects

      expect(described_class.for_term("Climate Resilience", 202710)).to eq("Climate Resilience (CRES)")
    end

    it "keeps a label that ends with its own code" do
      stub_subjects

      expect(described_class.for_term("Computer Science (COMP)", 202710)).to eq("Computer Science (COMP)")
    end

    # Banner labels CPFM "Facilities Management (CPCE)".
    it "replaces a code at the end of the label that is not the subject's code" do
      stub_subjects

      expect(described_class.for_term("Facilities Management (CPCE)", 202710)).to eq("Facilities Management (CPFM)")
    end

    it "keeps a bare code, and does not ask Banner" do
      expect(described_class.for_term("COMP", 202710)).to eq("COMP")
      expect(a_request(:get, subjects_url)).not_to have_been_made
    end

    it "keeps the stored label when it has a code and the same name, and does not ask Banner" do
      expect(described_class.for_term("Climate Resilience", 202710, stored: "Climate Resilience (CRES)"))
        .to eq("Climate Resilience (CRES)")
      expect(described_class.for_term("Facilities Management (CPCE)", 202710, stored: "Facilities Management (CPFM)"))
        .to eq("Facilities Management (CPFM)")
      expect(a_request(:get, subjects_url)).not_to have_been_made
    end

    it "keeps the label and reports the error when Banner fails" do
      stub_subjects(status: 400)
      allow(Rails.error).to receive(:report)

      expect(described_class.for_term("Climate Resilience", 202710)).to eq("Climate Resilience")
      expect(Rails.error).to have_received(:report).with(an_instance_of(Catalog::LeopardWebClient::RequestError),
                                                         handled: true, context: { term_uid: 202710 })
    end
  end

  describe ".codes" do
    around do |example|
      original = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      example.run
    ensure
      Rails.cache = original
    end

    it "asks Banner once for each term" do
      stub = stub_subjects

      2.times { described_class.codes(202710) }

      expect(described_class.codes(202710)).to include("Climate Resilience" => "CRES", "Computer Science (COMP)" => "COMP")
      expect(stub).to have_been_requested.once
    end

    it "does not keep a failed answer" do
      stub = stub_subjects(status: 400)
      allow(Rails.error).to receive(:report)

      2.times { described_class.codes(202710) }

      expect(stub).to have_been_requested.twice
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe Catalog::InstructorQuery do
  def teaching(term: create(:term), **attributes)
    create(:faculty, **attributes).tap { |faculty| create(:course, term: term).faculties << faculty }
  end

  it "lists only faculty who teach, by last name" do
    zed = teaching(last_name: "Zed")
    abe = teaching(last_name: "Abe")
    create(:faculty, last_name: "Idle")

    expect(described_class.new.call.to_a).to eq([ abe, zed ])
  end

  it "limits the list to one term" do
    term = create(:term)
    here = teaching(term: term)
    teaching

    expect(described_class.new.call(term_uid: term.uid).to_a).to eq([ here ])
  end

  it "matches every word against the first, last, or display name" do
    ada = teaching(first_name: "Ada", last_name: "Lovelace")
    teaching(first_name: "Ada", last_name: "Byron")

    expect(described_class.new.call(q: "  Ada   LOVE ").to_a).to eq([ ada ])
  end

  it "falls back to the name match when a semantic search cannot run" do
    ada = teaching(first_name: "Ada")
    allow(Catalog::SemanticSearch).to receive(:ranked_scope).and_return(nil)

    expect(described_class.new.call(q: "ada", semantic: true).to_a).to eq([ ada ])
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe Catalog::ReimportPlan do
  def banner_lists(*uids)
    allow(Catalog::LeopardWebClient).to receive(:get_active_terms)
      .and_return({ success: true, terms: uids.map { |uid| { code: uid.to_s, description: "Term #{uid}" } } })
  end

  before do
    create(:term, uid: 202620, year: 2026, season: :spring)
    create(:term, uid: 202710, year: 2026, season: :fall)
    create(:term, uid: 202720, year: 2027, season: :spring)
    create(:term, uid: 201420, year: 2014, season: :spring)
  end

  it "plans the terms that Banner lists and we have, newest first" do
    banner_lists(202620, 202720, 202710, 202730)

    plan = described_class.new.call

    expect(plan.term_uids).to eq([ 202720, 202710, 202620 ])
    expect(plan.missing_in_database).to eq([ 202730 ])
    expect(plan.missing_in_banner).to eq([ 201420 ])
  end

  it "keeps only the terms between FROM and TO" do
    banner_lists(202620, 202710, 202720)

    expect(described_class.new(from: "202700", to: "202710").call.term_uids).to eq([ 202710 ])
    expect(described_class.new(from: "", to: nil).call.term_uids).to eq([ 202720, 202710, 202620 ])
  end

  it "raises when Banner does not list its terms" do
    allow(Catalog::LeopardWebClient).to receive(:get_active_terms).and_return({ success: false, error: "down", terms: [] })

    expect { described_class.new.call }.to raise_error(Catalog::LeopardWebClient::RequestError, /down/)
  end
end

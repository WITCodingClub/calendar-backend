# frozen_string_literal: true

require "rails_helper"

RSpec.describe Catalog::CreditHoursRepairJob do
  it "repairs the term" do
    term = create(:term)
    allow(Catalog::CreditHoursRepair).to receive(:call).and_return(checked: 2, changed: 1)

    described_class.perform_now(term.uid)

    expect(Catalog::CreditHoursRepair).to have_received(:call).with(term)
  end

  it "does nothing for an unknown term" do
    allow(Catalog::CreditHoursRepair).to receive(:call)

    described_class.perform_now(1)

    expect(Catalog::CreditHoursRepair).not_to have_received(:call)
  end

  it "runs one term at a time under a fixed group" do
    expect(described_class.concurrency_group).to eq("Catalog::CreditHoursRepairJob")
  end
end

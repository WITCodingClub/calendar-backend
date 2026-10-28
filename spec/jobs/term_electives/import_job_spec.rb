# frozen_string_literal: true

require "rails_helper"

RSpec.describe TermElectives::ImportJob do
  it "runs the import" do
    importer = instance_double(TermElectives::Importer, call: :result)
    allow(TermElectives::Importer).to receive(:new).and_return(importer)

    expect(described_class.perform_now).to eq(:result)
  end
end

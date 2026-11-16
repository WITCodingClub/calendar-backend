# frozen_string_literal: true

require "rails_helper"

RSpec.describe BearerToken do
  it "reads the token after Bearer" do
    expect(described_class.from("Bearer abc.def")).to eq("abc.def")
  end

  it "gives nil for a missing or empty header" do
    expect([ described_class.from(nil), described_class.from(""), described_class.from("Bearer ") ]).to eq([ nil, nil, nil ])
  end
end

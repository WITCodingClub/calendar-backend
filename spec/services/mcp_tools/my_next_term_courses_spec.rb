# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpTools::MyNextTermCourses, :degree_planning do
  let(:user) { create(:user) }

  def call(scopes: McpTools::Scopes::NAMES, **arguments)
    described_class.call(server_context: mcp_context(user, scopes: scopes), **arguments)
  end

  def text(result) = result.content.first[:text]

  it "needs the programs:read scope" do
    result = call(scopes: McpTools::Scopes.expand("read"))

    expect(result.error?).to be(true)
    expect(text(result)).to include("Your programs")
  end

  it "says in its description that it is not a degree audit or a registration check" do
    expect(described_class.description_value).to include("not a degree audit or a registration check")
  end

  it "answers with a tool error for a bad term, and says how to add a program" do
    expect(text(call(term: "Winter 2027"))).to include("Banner term code")
    expect(text(call(term: "Spring 2027"))).to include("process a term")
  end

  it "answers with a tool error for an assume value that is not a course code" do
    expect(text(call(assume: [ "Widgets" ]))).to include("course codes such as COMP3350")
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpTools::UpdateMyPlannedPrograms do
  let(:user) { create(:user) }
  let!(:catalog_year) { create(:catalog_year, :imported, start_year: 2026) }
  let(:minor) { create(:degree_program, :minor, slug: "gear-minor", name: "Gear Minor") }

  before { create(:requirement_set, degree_program: minor, catalog_year: catalog_year, name: "Gear Minor") }

  def call(scopes: McpTools::Scopes::NAMES, **arguments)
    described_class.call(server_context: mcp_context(user, scopes: scopes), **arguments)
  end

  def text(result) = result.content.first[:text]

  it "needs the programs:write scope, which programs:read does not give" do
    result = call(scopes: %w[catalog programs:read], action: "add", program: "gear-minor")

    expect(result.error?).to be(true)
    expect(text(result)).to include("Change planned programs")
    expect(user.student_programs).to be_empty
  end

  it "says in its description that it needs the permission and does not declare the program" do
    expect(described_class.description_value).to include("does not declare the program", "Change planned programs")
  end

  it "adds a planned program and lists the planned programs" do
    result = call(action: "add", program: "gear-minor").structured_content

    row = user.student_programs.sole
    expect(row).to have_attributes(status: "planned", role: "minor", degree_program: minor)
    expect(result).to include(result: "added", program: include(id: row.public_id, program: "gear-minor", catalog_year: "2026-2027"))
    expect(result[:planned_programs].pluck(:id)).to eq([ row.public_id ])
    expect(result[:advisory][:message]).to eq(McpTools::BaseTool::ADVISORY)
  end

  it "removes a planned program by slug or by id" do
    by_slug = create(:student_program, :planned, catalog_year: catalog_year, user: user, degree_program: minor)

    expect(call(action: "remove", program: "gear-minor").structured_content).to include(result: "removed", planned_programs: [])
    expect(StudentProgram.exists?(by_slug.id)).to be(false)

    by_id = create(:student_program, :planned, catalog_year: catalog_year, user: user)
    expect(call(action: "remove", program: by_id.public_id).structured_content[:result]).to eq("removed")
    expect(StudentProgram.exists?(by_id.id)).to be(false)
  end

  it "never removes a LeopardWeb program or another student's planned program" do
    active = create(:student_program, user: user, degree_program: minor)
    other = create(:student_program, :planned, catalog_year: catalog_year, degree_program: minor)

    expect(text(call(action: "remove", program: active.public_id))).to include("No planned program", "my_programs")
    expect(text(call(action: "remove", program: other.public_id))).to include("No planned program")
    expect(text(call(action: "remove", program: "gear-minor"))).to include("No planned program")
    expect(StudentProgram.where(id: [ active.id, other.id ]).count).to eq(2)
  end

  it "answers a bad argument with a tool error" do
    expect(text(call(action: "add", program: "basket-weaving-bs"))).to include("No program basket-weaving-bs in the 2026-2027 catalog")
    expect(text(call(action: "add", program: "gear-minor", catalog_year: "2016-2017"))).to include("No 2016-2017 catalog")
    expect(text(call(action: "rename", program: "gear-minor"))).to include("action must be add or remove")
    expect(text(call(action: "remove", program: "gear-minor", catalog_year: "2026-2027"))).to include("only for add")

    create(:student_program, :minor, user: user, degree_program: minor)
    expect(text(call(action: "add", program: "gear-minor"))).to include("already in your programs")
  end

  describe "confirmation" do
    def confirmed_call(context = {}, **arguments)
      described_class.call(server_context: mcp_modern_context(user, **context), **arguments)
    end

    it "asks before it adds, names the program and its catalog year, and changes nothing until the student accepts" do
      question = confirmed_call(action: "add", program: "gear-minor")

      expect(question.input_requests.dig(McpTools::Confirmation::KEY, :params, :message)).to eq(
        "Add Gear Minor (2026-2027 catalog) to your planned programs in WIT Calendar. This is a plan only. " \
        "It does not declare the program at Wentworth."
      )
      expect(user.student_programs).to be_empty

      answer = ->(action) { confirmed_call({ input_responses: mcp_confirmation(action), request_state: question.request_state }, action: "add", program: "gear-minor") }
      expect(answer.call("decline").structured_content).to include(result: "unchanged", program: nil, not_changed: include(reason: "declined"))
      expect(user.student_programs).to be_empty

      expect(answer.call("accept").structured_content[:result]).to eq("added")
      expect(user.student_programs.planned.count).to eq(1)
    end

    it "asks before it removes" do
      create(:student_program, :planned, catalog_year: catalog_year, user: user, name: "Gear Minor", degree_program: minor)

      question = confirmed_call(action: "remove", program: "gear-minor")

      expect(question.input_requests.dig(McpTools::Confirmation::KEY, :params, :message))
        .to eq("Remove Gear Minor (2026-2027 catalog) from your planned programs in WIT Calendar.")
      expect(user.student_programs.planned.count).to eq(1)
    end
  end
end

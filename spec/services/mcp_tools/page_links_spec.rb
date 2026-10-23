# frozen_string_literal: true

require "rails_helper"

# The resource_link content items that point a student to a WIT Calendar page.
# spec/requests/mcp/page_links_spec.rb opens each page as a signed-in student.
RSpec.describe McpTools::PageLinks do
  let(:term)   { create(:term) }
  let(:user)   { create(:enrollment, course: create(:course, term: term)).user }
  let(:friend) { create(:user) }

  # The tools with links, the arguments of a call that succeeds, and the
  # controller action of each link.
  let(:linked_tools) do
    {
      McpTools::MyCourses              => [ { term_uid: term.uid }, [ "dashboard/schedules#show" ] ],
      McpTools::ListFriends            => [ {}, [ "dashboard/friends#index" ] ],
      McpTools::FriendBusyTimes        => [
        { friend_id: friend.public_id, start_date: "2026-12-17", end_date: "2026-12-18" }, [ "dashboard/friends#show" ]
      ],
      McpTools::MyCalendarSettings     => [ {}, [ "dashboard/calendar_preferences#index" ] ],
      McpTools::UpdateCalendarSettings => [ { level: "all_classes", color: "sage" }, [ "dashboard/calendar_preferences#index" ] ],
      McpTools::SetNotifications       => [ { disabled: true }, [ "dashboard/notifications#show" ] ]
    }
  end

  def request_with(version)
    headers = version ? { "HTTP_MCP_PROTOCOL_VERSION" => version } : {}
    ActionDispatch::TestRequest.create(headers)
  end

  def call(tool, scopes: McpTools::Scopes::NAMES, version: "2025-06-18", **arguments)
    tool.call(server_context: mcp_context(user, scopes: scopes, request: request_with(version)), **arguments)
  end

  def types(result) = result.content.map { |item| item[:type] }

  # The dashboard routes are inside Devise's authenticate block, which asks
  # Warden for a user. recognize_path builds a request with no Warden, so the
  # request here gets a Warden double that signs anyone in.
  def route_of(uri)
    path   = URI(uri).path
    env    = Rack::MockRequest.env_for(path).merge("warden" => instance_double(Warden::Proxy, authenticate!: user))
    route  = Rails.application.routes.recognize_path_with_request(ActionDispatch::Request.new(env), path, {})
    "#{route[:controller]}##{route[:action]}"
  end

  before do
    friendship = create(:friendship, :accepted, requester: user, addressee: friend)
    friendship.update_visibility_for!(friend, :availability_only)
  end

  it "covers every tool that declares links" do
    expect(McpTools.all.select(&:links_block)).to match_array(linked_tools.keys)
  end

  it "adds a resource_link to a page the router knows, after the JSON text" do
    linked_tools.each do |tool, (arguments, routes)|
      result = call(tool, **arguments)
      text, *links = result.content

      expect(result.error?).to be(false), "#{tool.name_value}: #{text[:text]}"
      expect(JSON.parse(text[:text])).to eq(JSON.parse(result.structured_content.to_json))
      expect(links.map { |link| route_of(link[:uri]) }).to eq(routes), tool.name_value
      expect(links).to all(include(type: "resource_link", mimeType: "text/html", name: a_string_starting_with("wit-calendar-")))
      expect(links.map { |link| URI(link[:uri]).host }).to all(eq("example.com"))
    end
  end

  it "keeps the links out of the structured content" do
    result = call(McpTools::ListFriends)

    expect(result.structured_content.keys).to eq([ :friends ])
    expect(result.structured_content.to_json).not_to include("resource_link")
  end

  it "puts only the public ids that the page uses in a URL" do
    my_courses = call(McpTools::MyCourses, term_uid: term.uid).content.last[:uri]
    friend_page = call(McpTools::FriendBusyTimes, friend_id: friend.public_id, start_date: "2026-12-17", end_date: "2026-12-18")
                  .content.last[:uri]

    expect(my_courses).to eq("http://example.com/dashboard/schedule?term_uid=#{term.uid}")
    expect(friend_page).to eq("http://example.com/dashboard/friends/#{friend.public_id}?week_start=2026-12-17")
  end

  it "gives a tool without links only the JSON text" do
    expect(McpTools::ListTerms.links_block).to be_nil
    expect(types(call(McpTools::ListTerms))).to eq([ "text" ])
  end

  it "gives a tool error no page link" do
    result = call(McpTools::FriendBusyTimes, friend_id: "nobody", start_date: "2026-12-17", end_date: "2026-12-18")

    expect(result.error?).to be(true)
    expect(types(result)).to eq([ "text" ])
  end

  it "links a missing permission to the connected apps card" do
    result = call(McpTools::SetNotifications, scopes: [ "catalog" ], disabled: true)

    expect(result.error?).to be(true)
    expect(result.content.first[:text]).to include("permission")
    link = result.content.second
    expect(link).to include(type: "resource_link", uri: "http://example.com/dashboard/settings#connected-apps")
    expect(route_of(link[:uri])).to eq("dashboard/settings#show")
  end

  describe "the protocol version" do
    it "sends links from 2025-06-18 on" do
      %w[2025-06-18 2025-11-25 2026-07-28].each do |version|
        expect(types(call(McpTools::ListFriends, version: version))).to eq(%w[text resource_link]), version
      end
    end

    it "sends no links to an older client or a request with no version header" do
      [ "2025-03-26", "2024-11-05", nil ].each do |version|
        expect(types(call(McpTools::ListFriends, version: version))).to eq([ "text" ]), version.inspect
        expect(types(call(McpTools::SetNotifications, scopes: [ "catalog" ], version: version, disabled: true))).to eq([ "text" ])
      end
    end

    it "reads the version of the _meta envelope first" do
      key     = MCP::RequestEnvelope::PROTOCOL_VERSION_META_KEY.to_sym
      context = mcp_context(user, request: request_with(nil), _meta: { key => "2026-07-28" })

      expect(types(McpTools::ListFriends.call(server_context: context))).to eq(%w[text resource_link])
    end
  end

  it "links my_courses only to a term that the schedule page lists" do
    past = create(:term, year: 2025)
    create(:enrollment, user: user, course: create(:course, term: past))
    allow(Term).to receive(:current).and_return(term)

    expect(types(call(McpTools::MyCourses, term_uid: term.uid))).to eq(%w[text resource_link])
    expect(types(call(McpTools::MyCourses, term_uid: past.uid))).to eq([ "text" ])
  end

  it "links my_courses to no page for a term without courses" do
    empty = create(:term)

    expect(types(call(McpTools::MyCourses, term_uid: empty.uid))).to eq([ "text" ])
  end

  context "when the student has no processed courses" do
    let(:user) { create(:user) }

    it "links only to the pages that skip onboarding" do
      expect(types(call(McpTools::ListFriends))).to eq([ "text" ])
      expect(types(call(McpTools::MyCalendarSettings))).to eq([ "text" ])
      expect(types(call(McpTools::FriendBusyTimes, friend_id: friend.public_id, start_date: "2026-12-17", end_date: "2026-12-18")))
        .to eq([ "text" ])
      expect(types(call(McpTools::SetNotifications, disabled: true))).to eq(%w[text resource_link])
    end

    it "links an admin to every page, the same as the dashboard" do
      user.update!(access_level: :admin)

      expect(types(call(McpTools::ListFriends))).to eq(%w[text resource_link])
    end
  end

  it "describes the friend page for a friend who shares the full schedule" do
    Flipper.enable_actor(FeatureFlags::FRIENDS_AVAILABILITY_ONLY, user)
    Friendship.accepted_between(user, friend).update_visibility_for!(friend, :full)

    link = call(McpTools::FriendBusyTimes, friend_id: friend.public_id, start_date: "2026-12-17", end_date: "2026-12-18")
           .content.last

    expect(link[:description]).to eq("What this friend shares with you: their class schedule, or only the times they are busy.")
  ensure
    Flipper.disable(FeatureFlags::FRIENDS_AVAILABILITY_ONLY)
  end

  it "reports a fault in a links block and sends the result without links" do
    allow(McpTools::ListFriends).to receive(:links_block).and_return(proc { raise "broken link" })
    allow(Rails.error).to receive(:report)

    result = call(McpTools::ListFriends)

    expect(result.error?).to be(false)
    expect(types(result)).to eq([ "text" ])
    expect(Rails.error).to have_received(:report)
      .with(an_instance_of(RuntimeError), handled: true, context: { user_id: user.id })
  end
end

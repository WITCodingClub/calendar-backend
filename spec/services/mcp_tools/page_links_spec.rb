# frozen_string_literal: true

require "rails_helper"

# The resource_link content items that point a student to a WIT Calendar page.
# spec/requests/mcp/page_links_spec.rb opens each page as a signed-in student.
RSpec.describe McpTools::PageLinks do
  let(:user)   { create(:user) }
  let(:friend) { create(:user) }
  let(:term)   { create(:term) }

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

  def call(tool, scopes: McpTools::Scopes::NAMES, **arguments)
    tool.call(server_context: mcp_context(user, scopes: scopes), **arguments)
  end

  # The dashboard routes are inside Devise's authenticate block, which asks
  # Warden for a user. recognize_path builds a request with no Warden, so the
  # request here gets a Warden double that signs anyone in.
  def route_of(uri)
    path    = URI(uri).path
    env     = Rack::MockRequest.env_for(path).merge("warden" => instance_double(Warden::Proxy, authenticate!: user))
    routes  = Rails.application.routes
    route   = routes.recognize_path_with_request(ActionDispatch::Request.new(env), path, {})
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
    result = call(McpTools::ListTerms)

    expect(McpTools::ListTerms.links_block).to be_nil
    expect(result.content.map { |item| item[:type] }).to eq([ "text" ])
  end

  it "gives a tool error no page link" do
    result = call(McpTools::FriendBusyTimes, friend_id: "nobody", start_date: "2026-12-17", end_date: "2026-12-18")

    expect(result.error?).to be(true)
    expect(result.content.map { |item| item[:type] }).to eq([ "text" ])
  end

  it "links a missing permission to the connected apps card" do
    result = call(McpTools::SetNotifications, scopes: [ "catalog" ], disabled: true)

    expect(result.error?).to be(true)
    expect(result.content.first[:text]).to include("permission")
    link = result.content.second
    expect(link).to include(type: "resource_link", uri: "http://example.com/dashboard/settings#connected-apps")
    expect(route_of(link[:uri])).to eq("dashboard/settings#show")
  end
end

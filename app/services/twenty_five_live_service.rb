# frozen_string_literal: true

require "cgi"

class TwentyFiveLiveService < ApplicationService
  require "faraday"
  require "nokogiri"

  BASE_URL = "https://webservices.collegenet.com/r25ws/wrd/wit/run/"
  NS = { "r25" => "http://www.collegenet.com/r25" }.freeze

  attr_reader :action

  def initialize(action:)
    @action = action
    super()
  end

  def call
    case action
    when :sync_events
      sync_events
    else
      raise ArgumentError, "Unknown action: #{action}"
    end
  end

  def call!
    call
  end

  def self.sync_events
    new(action: :sync_events).call
  end

  def connection
    username = Rails.application.credentials.dig(:TwentyFiveLive, :username)
    password = Rails.application.credentials.dig(:TwentyFiveLive, :password)

    @connection ||= Faraday.new(url: BASE_URL) do |faraday|
      faraday.request :authorization, :basic, username, password
      faraday.adapter Faraday.default_adapter
    end
  end

  private

  def sync_events
    start_dt = Time.zone.today.strftime("%Y%m%d")
    end_dt   = (Time.zone.today + 1.year).strftime("%Y%m%d")

    result       = { created: 0, updated: 0, unchanged: 0, errors: [] }
    current_page = 1
    total_pages  = nil

    loop do
      doc, page_index, total_pages_from_doc = fetch_events_page_xml(
        start_dt: start_dt,
        end_dt: end_dt,
        page: current_page
      )

      total_pages ||= total_pages_from_doc || current_page

      Rails.logger.info("[TwentyFiveLiveService] events.xml page #{page_index}/#{total_pages}")

      doc.xpath("//r25:event", NS).each do |node|
        upsert_event(node, result)
      rescue => e
        result[:errors] << { page: current_page, error: e.message }
        Rails.logger.error("[TwentyFiveLiveService] Error parsing event: #{e.message}")
      end

      break if current_page >= total_pages

      current_page += 1
    end

    result
  end

  def fetch_events_page_xml(start_dt:, end_dt:, page:, page_size: 100)
    params = {
      scope: "extended",
      include: "reservations",
      start_dt: start_dt,
      end_dt: end_dt,
      paginate: nil,
      page: page,
      page_size: page_size,
      node_type: "E"
    }

    response = connection.get("events.xml", params.compact)

    Rails.logger.info("[TwentyFiveLiveService] events.xml page=#{page} status=#{response.status}")

    raise "HTTP #{response.status} fetching events.xml" unless response.status == 200

    body = response.body
    raise "Empty events.xml body" if body.nil? || body.strip.empty?

    doc  = Nokogiri::XML(body)
    root = doc.root

    page_index  = (root["page_index"] || root["pageIndex"] || page).to_i
    total_pages = (root["total_pages"] || root["totalPages"]).to_i
    total_pages = 1 if total_pages.zero?

    [doc, page_index, total_pages]
  end

  def upsert_event(node, result)
    attrs = parse_event_attrs(node)
    event = TwentyFiveLive::Event.find_or_initialize_by(event_id: attrs[:event_id])

    event.assign_attributes(attrs)
    if event.new_record?
      event.save!
      result[:created] += 1
    else
      if event.changed?
        event.save!
        result[:updated] += 1
      else
        result[:unchanged] += 1
      end
    end

    event.update!(last_synced_at: Time.current)

    upsert_organizations(node, event)
    upsert_categories(node, event)
    upsert_reservations(node, event)
  end

  def parse_event_attrs(node)
    description_node = node.at_xpath(
      "r25:event_text[r25:text_type_id[text()='1']]/r25:text", NS
    )
    raw_description = description_node&.text
    description = raw_description ? CGI.unescapeHTML(raw_description) : nil

    public_attr = node.at_xpath(
      "r25:custom_attribute[r25:attribute_id[text()='32']]/r25:attribute_value", NS
    )

    {
      event_id: node.at_xpath("r25:event_id", NS)&.text&.to_i,
      event_locator: node.at_xpath("r25:event_locator", NS)&.text,
      event_name: node.at_xpath("r25:event_name", NS)&.text,
      event_title: node.at_xpath("r25:event_title", NS)&.text.presence,
      start_date: node.at_xpath("r25:start_date", NS)&.text,
      end_date: node.at_xpath("r25:end_date", NS)&.text,
      event_type_id: node.at_xpath("r25:event_type_id", NS)&.text&.to_i,
      event_type_name: node.at_xpath("r25:event_type_name", NS)&.text,
      state: node.at_xpath("r25:state", NS)&.text&.to_i,
      state_name: node.at_xpath("r25:state_name",      NS)&.text,
      cabinet_id: node.at_xpath("r25:cabinet_id",      NS)&.text&.to_i,
      cabinet_name: node.at_xpath("r25:cabinet_name", NS)&.text,
      description: description,
      registration_url: node.at_xpath("r25:registration_url", NS)&.text.presence,
      public_website: public_attr&.text == "T",
      last_mod_dt: node.at_xpath("r25:last_mod_dt",     NS)&.text,
      creation_dt: node.at_xpath("r25:creation_dt",     NS)&.text
    }
  end

  def upsert_organizations(node, event)
    node.xpath("r25:organization", NS).each do |org_node|
      org_id = org_node.at_xpath("r25:organization_id", NS)&.text&.to_i
      next unless org_id

      type_node = org_node.at_xpath("r25:organization_details/r25:organization_type", NS)

      org = TwentyFiveLive::Organization.find_or_initialize_by(organization_id: org_id)
      org.update!(
        organization_name: org_node.at_xpath("r25:organization_name", NS)&.text,
        organization_title: org_node.at_xpath("r25:organization_title", NS)&.text,
        organization_type_id: type_node&.at_xpath("r25:organization_type_id", NS)&.text&.to_i,
        organization_type_name: type_node&.at_xpath("r25:organization_type_name", NS)&.text
      )

      primary_flag = org_node.at_xpath("r25:primary", NS)&.text == "T"
      TwentyFiveLive::EventOrganization.find_or_create_by(
        twenty_five_live_event_id: event.id,
        twenty_five_live_organization_id: org.id
      ) do |eo|
        eo.primary = primary_flag
      end
    end
  end

  def upsert_categories(node, event)
    node.xpath("r25:category", NS).each do |cat_node|
      cat_id = cat_node.at_xpath("r25:category_id", NS)&.text&.to_i
      next unless cat_id

      cat = TwentyFiveLive::Category.find_or_initialize_by(category_id: cat_id)
      cat.update!(category_name: cat_node.at_xpath("r25:category_name", NS)&.text)

      TwentyFiveLive::EventCategory.find_or_create_by(
        twenty_five_live_event_id: event.id,
        twenty_five_live_category_id: cat.id
      )
    end
  end

  def upsert_reservations(node, event)
    expected_count = node.at_xpath("r25:expected_count", NS)&.text&.to_i

    node.xpath("r25:profile/r25:reservation", NS).each do |res_node|
      res_id = res_node.at_xpath("r25:reservation_id", NS)&.text&.to_i
      next unless res_id

      reservation = TwentyFiveLive::Reservation.find_or_initialize_by(reservation_id: res_id)
      reservation.update!(
        twenty_five_live_event_id: event.id,
        event_start_dt: res_node.at_xpath("r25:event_start_dt", NS)&.text,
        event_end_dt: res_node.at_xpath("r25:event_end_dt", NS)&.text,
        reservation_state: res_node.at_xpath("r25:reservation_state", NS)&.text&.to_i,
        expected_count: expected_count
      )

      upsert_space_reservations(res_node, reservation)
    end
  end

  def upsert_space_reservations(res_node, reservation)
    res_node.xpath("r25:space_reservation", NS).each do |sr_node|
      space_id = sr_node.at_xpath("r25:space_id", NS)&.text&.to_i
      next unless space_id

      space_node = sr_node.at_xpath("r25:space", NS)
      space = TwentyFiveLive::Space.find_or_initialize_by(space_id: space_id)
      space.update!(
        space_name: space_node&.at_xpath("r25:space_name", NS)&.text,
        formal_name: space_node&.at_xpath("r25:formal_name", NS)&.text,
        building_name: space_node&.at_xpath("r25:building_name", NS)&.text,
        max_capacity: space_node&.at_xpath("r25:max_capacity", NS)&.text&.to_i
      )

      TwentyFiveLive::SpaceReservation.find_or_create_by(
        twenty_five_live_reservation_id: reservation.id,
        twenty_five_live_space_id: space.id
      ) do |sr|
        sr.layout_id                = sr_node.at_xpath("r25:layout_id",   NS)&.text&.to_i
        sr.layout_name              = sr_node.at_xpath("r25:layout_name", NS)&.text
        sr.selected_layout_capacity = sr_node.at_xpath("r25:selected_layout_capacity", NS)&.text&.to_i
      end
    end
  end

end

# frozen_string_literal: true

module TwentyFiveLive
  class Client < ApplicationService
    require "net/http"

    BASE_URL = "https://webservices.collegenet.com/r25ws/wrd/wit/run/"

    class RequestError < StandardError
      attr_reader :status
      def initialize(msg, status: nil)
        @status = status
        super(msg)
      end
    end

    OPEN_TIMEOUT = 10
    READ_TIMEOUT = 30
    MAX_RETRIES  = 3

    def call
      call!
    rescue => e
      Rails.error.report(e, handled: true)
      false
    end

    def call!
      sync_organizations
      sync_event_categories
      sync_event_custom_attributes
      sync_resources
      sync_spaces
      check_constant_drift
      true
    end

    private

    def fetch(endpoint)
      uri = URI("#{BASE_URL}#{endpoint}.json")
      req = Net::HTTP::Get.new(uri)
      creds = Rails.application.credentials.dig(:TwentyFiveLive)
      req.basic_auth(creds[:username], creds[:password]) if creds

      attempts = 0
      begin
        attempts += 1
        res = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                              open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) { |h| h.request(req) }

        unless res.is_a?(Net::HTTPSuccess)
          raise RequestError.new("25Live API returned #{res.code} for #{endpoint}", status: res.code.to_i)
        end

        JSON.parse(res.body)
      rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, Errno::ECONNREFUSED => e
        retry if attempts < MAX_RETRIES
        raise
      rescue JSON::ParserError => e
        raise RequestError.new("25Live API returned non-JSON for #{endpoint}: #{e.message}")
      end
    end

    def sync_organizations
      data = fetch("organizations")
      orgs = Array.wrap(data.dig("organizations", "organization") ||
                        data.dig("r25:organizations", "r25:organization"))

      orgs.each do |raw|
        id   = (raw["organization_id"] || raw["r25:organization_id"])&.to_i
        name = (raw["organization_name"] || raw["r25:organization_name"])&.strip
        next unless id && name.present?

        TwentyFiveLive::Organization
          .find_or_initialize_by(twenty_five_live_id: id)
          .tap do |org|
            org.assign_attributes(
              code: (raw["organization_code"] || raw["r25:organization_code"])&.strip,
              name: name,
              organization_type_name: (raw["organization_type_name"] || raw["r25:organization_type_name"])&.strip
            )
            org.save! if org.new_record? || org.changed?
          end
      end
    end

    def sync_event_categories
      data = fetch("evcat")
      cats = Array.wrap(data.dig("categories", "category") ||
                        data.dig("r25:categories", "r25:category"))

      cats.each do |raw|
        id   = (raw["category_id"] || raw["r25:category_id"])&.to_i
        name = (raw["category_name"] || raw["r25:category_name"])&.strip
        next unless id && name.present?

        TwentyFiveLive::EventCategory
          .find_or_initialize_by(twenty_five_live_id: id)
          .tap do |cat|
            cat.assign_attributes(
              name: name,
              sort_order: (raw["sort_order"] || raw["r25:sort_order"])&.to_i,
              defn_state: (raw["defn_state"] || raw["r25:defn_state"])&.to_i
            )
            cat.save! if cat.new_record? || cat.changed?
          end
      end
    end

    def sync_event_custom_attributes
      data = fetch("evatrb")
      attrs = Array.wrap(data.dig("custom_attributes", "custom_attribute") ||
                         data.dig("r25:custom_attributes", "r25:custom_attribute"))

      attrs.each do |raw|
        id   = (raw["custom_attribute_id"] || raw["r25:custom_attribute_id"])&.to_i
        name = (raw["custom_attribute_name"] || raw["r25:custom_attribute_name"])&.strip
        next unless id && name.present?

        TwentyFiveLive::EventCustomAttribute
          .find_or_initialize_by(twenty_five_live_id: id)
          .tap do |eca|
            eca.assign_attributes(
              name: name,
              attribute_type: raw["attribute_type"] || raw["r25:attribute_type"],
              attribute_type_name: (raw["attribute_type_name"] || raw["r25:attribute_type_name"])&.strip,
              multi_val: raw["multi_val"] || raw["r25:multi_val"],
              sort_order: (raw["sort_order"] || raw["r25:sort_order"])&.to_i,
              defn_state: (raw["defn_state"] || raw["r25:defn_state"])&.to_i
            )
            eca.save! if eca.new_record? || eca.changed?
          end
      end
    end

    def sync_resources
      data = fetch("resources")
      resources = Array.wrap(data.dig("resources", "resource") ||
                             data.dig("r25:resources", "r25:resource"))

      resources.each do |raw|
        id   = (raw["resource_id"] || raw["r25:resource_id"])&.to_i
        name = (raw["resource_name"] || raw["r25:resource_name"])&.strip
        next unless id && name.present?

        TwentyFiveLive::Resource
          .find_or_initialize_by(twenty_five_live_id: id)
          .tap do |res|
            res.assign_attributes(
              name: name,
              stock_level: (raw["stock_level"] || raw["r25:stock_level"])&.to_i,
              assign_perm: raw["assign_perm"] || raw["r25:assign_perm"],
              schedule_perm: raw["schedule_perm"] || raw["r25:schedule_perm"]
            )
            res.save! if res.new_record? || res.changed?
          end
      end
    end

    def sync_spaces
      data   = fetch("spaces")
      spaces = Array.wrap(data.dig("spaces", "space") ||
                          data.dig("r25:spaces", "r25:space"))

      buildings_by_abbr = Building.all.index_by { |b| b.abbreviation.upcase }

      spaces.each do |raw|
        space_id    = (raw["space_id"]    || raw["r25:space_id"])&.to_i
        formal_name = (raw["formal_name"] || raw["r25:formal_name"])&.strip
        space_name  = (raw["space_name"]  || raw["r25:space_name"])&.strip
        bldg_25_id  = (raw["building_id"] || raw["r25:building_id"])&.to_i
        bldg_formal = (raw["building_name"] || raw["r25:building_name"])&.strip
        capacity    = (raw["max_capacity"] || raw["r25:max_capacity"]).to_i

        next unless space_id && space_name.present?

        # space_name encodes "ABBREV ROOM_NUMBER" (e.g. "WENTW 310")
        abbrev, room_number = space_name.split(" ", 2)
        next unless room_number.present?

        building = buildings_by_abbr[abbrev.upcase]
        next unless building
        next if building.tbd?

        if bldg_25_id&.positive?
          attrs = {}
          attrs[:twenty_five_live_id] = bldg_25_id if building.twenty_five_live_id.nil?
          attrs[:formal_name]         = bldg_formal if bldg_formal.present? && building.formal_name.nil?
          building.update!(attrs) if attrs.any?
        end

        room = building.rooms.find_by(number: room_number)
        next unless room
        next if room.tbd?

        attrs = {}
        attrs[:twenty_five_live_id] = space_id    if room.twenty_five_live_id.nil?
        attrs[:formal_name]         = formal_name if formal_name.present? && room.formal_name.nil?

        # Capacity is refreshed on every sync, unlike the ID and the formal
        # name. 25Live is the registrar's own record of how many seats a room
        # holds, and that number changes when a room is rebuilt. A capacity of
        # 0 means 25Live has no count, so leave the room unknown rather than
        # record a room with no seats.
        attrs[:capacity] = capacity if capacity.positive? && room.capacity != capacity

        room.update!(attrs) if attrs.any?
      end

      # Every building has now been looked for, found or not. The admin page
      # reads this to tell "not in 25Live" apart from "not synced yet".
      Building.update_all(twenty_five_live_checked_at: Time.current)
    end

    def check_constant_drift
      drifts = ConstantDrift.new(method(:fetch)).call
      TwentyFiveLiveMailer.constant_drift_notification(drifts).deliver_later if drifts.any?
    end
  end
end

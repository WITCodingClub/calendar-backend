# frozen_string_literal: true

module TwentyFiveLive
  class Client < ApplicationService
    BASE_URL = "https://webservices.collegenet.com/r25ws/wrd/wit/run/"

    class RequestError < StandardError
      attr_reader :status
      def initialize(msg, status: nil)
        @status = status
        super(msg)
      end
    end

    # The reference tables that copy one 25Live list each: the endpoint, the
    # list keys, the key of the id and name fields, and the other columns.
    ReferenceSync = Data.define(:model, :endpoint, :list, :key, :columns)

    REFERENCE_SYNCS = [
      ReferenceSync.new(TwentyFiveLive::Organization, "organizations", %w[organizations organization], "organization",
                        ->(raw) { { code: raw["organization_code"]&.strip, organization_type_name: raw["organization_type_name"]&.strip } }),
      ReferenceSync.new(TwentyFiveLive::EventCategory, "evcat", %w[categories category], "category",
                        ->(raw) { { sort_order: raw["sort_order"]&.to_i, defn_state: raw["defn_state"]&.to_i } }),
      ReferenceSync.new(TwentyFiveLive::EventCustomAttribute, "evatrb", %w[custom_attributes custom_attribute], "custom_attribute",
                        ->(raw) {
                          { attribute_type: raw["attribute_type"], attribute_type_name: raw["attribute_type_name"]&.strip,
                            multi_val: raw["multi_val"], sort_order: raw["sort_order"]&.to_i, defn_state: raw["defn_state"]&.to_i }
                        }),
      ReferenceSync.new(TwentyFiveLive::Resource, "resources", %w[resources resource], "resource",
                        ->(raw) { { stock_level: raw["stock_level"]&.to_i, assign_perm: raw["assign_perm"], schedule_perm: raw["schedule_perm"] } })
    ].freeze

    def call!
      REFERENCE_SYNCS.each { |sync| sync_reference(sync) }
      sync_spaces
      check_constant_drift
      true
    end

    private

    # The parsed body. 25Live names some keys with an "r25:" prefix and some
    # without, so the prefix is dropped here and the readers use the plain key.
    def fetch(endpoint)
      response = connection.get("#{endpoint}.json")
      unless response.success?
        raise RequestError.new("25Live API returned #{response.status} for #{endpoint}", status: response.status)
      end

      body = JSON.parse(response.body)
      raise RequestError, "25Live API returned a body that is not a JSON object for #{endpoint}" unless body.is_a?(Hash)

      body.deep_transform_keys { |key| key.delete_prefix("r25:") }
    rescue JSON::ParserError => e
      raise RequestError.new("25Live API returned non-JSON for #{endpoint}: #{e.message}")
    end

    def connection
      @connection ||= HttpFetcher.connection(url: BASE_URL) do |f|
        creds = Rails.application.credentials.dig(:TwentyFiveLive)
        f.request :authorization, :basic, creds[:username], creds[:password] if creds
      end
    end

    def sync_reference(sync)
      Array.wrap(fetch(sync.endpoint).dig(*sync.list)).each do |raw|
        id   = raw["#{sync.key}_id"]&.to_i
        name = raw["#{sync.key}_name"]&.strip
        next unless id && name.present?

        record = sync.model.find_or_initialize_by(twenty_five_live_id: id)
        record.assign_attributes(name: name, **sync.columns.call(raw))
        record.save! if record.new_record? || record.changed?
      end
    end

    def sync_spaces
      data   = fetch("spaces")
      spaces = Array.wrap(data.dig("spaces", "space"))

      buildings_by_abbr = Building.all.index_by { |b| b.abbreviation.upcase }

      spaces.each do |raw|
        space_id    = raw["space_id"]&.to_i
        formal_name = raw["formal_name"]&.strip
        space_name  = raw["space_name"]&.strip
        bldg_25_id  = raw["building_id"]&.to_i
        bldg_formal = raw["building_name"]&.strip
        capacity    = raw["max_capacity"].to_i

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

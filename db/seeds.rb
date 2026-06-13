# frozen_string_literal: true

# Organizations are DB-backed and populated from the 25Live API via the sync service.
# EventCategories and EventCustomAttributes are also DB-backed; they fall back to
# the constants below if the live sync fails (e.g. no credentials in CI).

puts "Seeding 25Live data from API..."
begin
  External::TwentyFiveLiveService.call!
  puts "  Sync complete — #{TwentyFiveLive::Organization.count} orgs, #{TwentyFiveLive::EventCategory.count} categories, #{TwentyFiveLive::EventCustomAttribute.count} custom attributes"
rescue => e
  puts "  API sync failed (#{e.message}), falling back to constants for categories and custom attributes"

  puts "  Seeding event categories from constants..."
  TwentyFiveLive::EventCategory::EVENT_CATEGORIES.each do |attrs|
    cat = TwentyFiveLive::EventCategory.find_or_initialize_by(twenty_five_live_id: attrs[:category_id])
    next unless cat.new_record?

    cat.assign_attributes(name: attrs[:category_name], sort_order: attrs[:sort_order], defn_state: attrs[:defn_state])
    cat.save!
  rescue ActiveRecord::RecordInvalid => e
    puts "    SKIP id=#{attrs[:category_id]}: #{e.message}"
  end

  puts "  Seeding event custom attributes from constants..."
  TwentyFiveLive::EventCustomAttribute::EVENT_CUSTOM_ATTRIBUTES.each do |attrs|
    eca = TwentyFiveLive::EventCustomAttribute.find_or_initialize_by(twenty_five_live_id: attrs[:attribute_id])
    next unless eca.new_record?

    eca.assign_attributes(
      name: attrs[:attribute_name], attribute_type: attrs[:attribute_type],
      attribute_type_name: attrs[:attribute_type_name], multi_val: attrs[:multi_val],
      sort_order: attrs[:sort_order], defn_state: attrs[:defn_state]
    )
    eca.save!
  rescue ActiveRecord::RecordInvalid => e
    puts "    SKIP id=#{attrs[:attribute_id]}: #{e.message}"
  end
end

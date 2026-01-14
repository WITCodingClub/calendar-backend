# frozen_string_literal: true

require "rails_helper"

RSpec.describe PreferenceResolver do
  let(:user) { create(:user) }
  let(:resolver) { described_class.new(user) }

  let(:term) { create(:term) }
  let(:course) { create(:course, schedule_type: "lecture", term: term) }
  let(:building) { create(:building) }
  let(:room) { create(:room, building: building) }
  let(:meeting_time) { create(:meeting_time, course: course, room: room) }

  describe "#resolve_for" do
    context "with no preferences set" do
      it "returns system defaults including UserExtensionConfig colors" do
        prefs = resolver.resolve_for(meeting_time)

        expect(prefs[:title_template]).to eq("{{title}}")
        expect(prefs[:description_template]).to eq("{{faculty}}\n{{faculty_email}}")
        expect(prefs[:location_template]).to eq("{{building}} {{room}}")
        expect(prefs[:reminder_settings]).to eq([{ "time" => "30", "type" => "minutes", "method" => "popup" }])
        # Color should come from UserExtensionConfig default (created by User after_create callback)
        expect(prefs[:color_id]).to eq(user.user_extension_config.default_color_lecture)
        expect(prefs[:visibility]).to eq("default")
      end
    end

    context "with UserExtensionConfig default colors" do
      before do
        # User automatically gets a UserExtensionConfig via after_create callback
        user.user_extension_config.update!(
          default_color_lecture: "#3f51b5",
          default_color_lab: "#616161"
        )
      end

      it "uses UserExtensionConfig lecture color for lecture courses" do
        prefs = resolver.resolve_for(meeting_time)
        expect(prefs[:color_id]).to eq("#3f51b5")
      end

      it "uses UserExtensionConfig lab color for laboratory courses" do
        lab_course = create(:course, schedule_type: "laboratory", term: term)
        lab_meeting = create(:meeting_time, course: lab_course, room: room)

        prefs = resolver.resolve_for(lab_meeting)
        expect(prefs[:color_id]).to eq("#616161")
      end

      it "falls back to hardcoded color for hybrid courses" do
        hybrid_course = create(:course, schedule_type: "hybrid", term: term)
        hybrid_meeting = create(:meeting_time, course: hybrid_course, room: room)

        prefs = resolver.resolve_for(hybrid_meeting)
        # Should use MeetingTime#event_color since there's no UserExtensionConfig field for hybrid
        expect(prefs[:color_id]).to be_present
      end

      context "with CalendarPreference overriding UserExtensionConfig" do
        let!(:event_type_pref) do
          create(:calendar_preference,
                 user: user,
                 scope: :event_type,
                 event_type: "lecture",
                 color_id: 9)
        end

        it "prefers CalendarPreference over UserExtensionConfig" do
          prefs = resolver.resolve_for(meeting_time)
          expect(prefs[:color_id]).to eq(9)
        end
      end
    end

    context "with global preference" do
      let!(:global_pref) do
        create(:calendar_preference,
               user: user,
               scope: :global,
               title_template: "Global: {{title}}",
               reminder_settings: [{ "time" => "30", "type" => "minutes", "method" => "popup" }],
               color_id: 5)
      end

      it "uses global preferences" do
        prefs = resolver.resolve_for(meeting_time)

        expect(prefs[:title_template]).to eq("Global: {{title}}")
        expect(prefs[:reminder_settings]).to eq([{ "time" => "30", "type" => "minutes", "method" => "popup" }])
        expect(prefs[:color_id]).to eq(5)
      end
    end

    context "with event type preference" do
      let!(:global_pref) do
        create(:calendar_preference,
               user: user,
               scope: :global,
               title_template: "Global: {{title}}",
               color_id: 1)
      end

      let!(:event_type_pref) do
        create(:calendar_preference,
               user: user,
               scope: :event_type,
               event_type: "lecture",
               title_template: "Lecture: {{title}}",
               reminder_settings: [{ "time" => "45", "type" => "minutes", "method" => "popup" }])
      end

      it "prefers event type over global" do
        prefs = resolver.resolve_for(meeting_time)

        expect(prefs[:title_template]).to eq("Lecture: {{title}}")
        expect(prefs[:reminder_settings]).to eq([{ "time" => "45", "type" => "minutes", "method" => "popup" }])
        expect(prefs[:color_id]).to eq(1) # Falls back to global
      end
    end

    context "with individual event preference" do
      let!(:global_pref) do
        create(:calendar_preference,
               user: user,
               scope: :global,
               title_template: "Global: {{title}}",
               color_id: 1)
      end

      let!(:event_type_pref) do
        create(:calendar_preference,
               user: user,
               scope: :event_type,
               event_type: "lecture",
               title_template: "Lecture: {{title}}",
               reminder_settings: [{ "time" => "45", "type" => "minutes", "method" => "popup" }])
      end

      let!(:individual_pref) do
        create(:event_preference,
               user: user,
               preferenceable: meeting_time,
               reminder_settings: [{ "time" => "60", "type" => "minutes", "method" => "popup" }])
      end

      it "prefers individual over event type and global" do
        prefs = resolver.resolve_for(meeting_time)

        expect(prefs[:title_template]).to eq("Lecture: {{title}}") # Falls back to event type
        expect(prefs[:reminder_settings]).to eq([{ "time" => "60", "type" => "minutes", "method" => "popup" }]) # Individual
        expect(prefs[:color_id]).to eq(1) # Falls back to global
      end
    end

    context "with laboratory schedule type" do
      let(:lab_course) { create(:course, schedule_type: "laboratory", term: term) }
      let(:lab_meeting) { create(:meeting_time, course: lab_course, room: room) }

      it "uses system default" do
        prefs = resolver.resolve_for(lab_meeting)

        expect(prefs[:title_template]).to eq("{{title}}")
      end

      context "with event type preference for laboratory" do
        let!(:lab_pref) do
          create(:calendar_preference,
                 user: user,
                 scope: :event_type,
                 event_type: "laboratory",
                 title_template: "Custom Lab: {{title}}",
                 color_id: 7)
        end

        it "uses laboratory preference" do
          prefs = resolver.resolve_for(lab_meeting)

          expect(prefs[:title_template]).to eq("Custom Lab: {{title}}")
          expect(prefs[:color_id]).to eq(7)
        end
      end
    end

    context "with hybrid schedule type" do
      let(:hybrid_course) { create(:course, schedule_type: "hybrid", term: term) }
      let(:hybrid_meeting) { create(:meeting_time, course: hybrid_course, room: room) }

      it "uses system default" do
        prefs = resolver.resolve_for(hybrid_meeting)

        expect(prefs[:title_template]).to eq("{{title}}")
      end
    end
  end

  describe "#resolve_with_sources" do
    let!(:global_pref) do
      create(:calendar_preference,
             user: user,
             scope: :global,
             title_template: "Global: {{title}}",
             color_id: 1,
             visibility: "default")
    end

    let!(:event_type_pref) do
      create(:calendar_preference,
             user: user,
             scope: :event_type,
             event_type: "lecture",
             reminder_settings: [{ "time" => "45", "type" => "minutes", "method" => "popup" }])
    end

    it "returns preferences with source information" do
      result = resolver.resolve_with_sources(meeting_time)

      expect(result[:preferences][:title_template]).to eq("Global: {{title}}")
      expect(result[:preferences][:reminder_settings]).to eq([{ "time" => "45", "type" => "minutes", "method" => "popup" }])
      expect(result[:preferences][:color_id]).to eq(1)

      expect(result[:sources][:title_template]).to eq("global")
      expect(result[:sources][:reminder_settings]).to eq("event_type:lecture")
      expect(result[:sources][:color_id]).to eq("global")
      expect(result[:sources][:visibility]).to eq("global")
    end

    context "with individual overrides" do
      let!(:individual_pref) do
        create(:event_preference,
               user: user,
               preferenceable: meeting_time,
               color_id: 9)
      end

      it "shows individual as source" do
        result = resolver.resolve_with_sources(meeting_time)

        expect(result[:preferences][:color_id]).to eq(9)
        expect(result[:sources][:color_id]).to eq("individual")
      end
    end

    context "with system defaults" do
      it "shows system_default as source for unset values" do
        result = resolver.resolve_with_sources(meeting_time)

        expect(result[:sources][:description_template]).to eq("system_default")
      end
    end
  end

  describe "caching" do
    it "caches resolved preferences for the same event" do
      # First call
      prefs1 = resolver.resolve_for(meeting_time)

      # Modify preferences in database
      create(:calendar_preference,
             user: user,
             scope: :global,
             title_template: "New Global: {{title}}")

      # Second call should return cached value
      prefs2 = resolver.resolve_for(meeting_time)

      expect(prefs2[:title_template]).to eq(prefs1[:title_template])
    end

    it "uses different cache keys for different events" do
      other_meeting = create(:meeting_time, course: course, room: room)

      create(:event_preference,
             user: user,
             preferenceable: meeting_time,
             color_id: 5)

      create(:event_preference,
             user: user,
             preferenceable: other_meeting,
             color_id: 7)

      prefs1 = resolver.resolve_for(meeting_time)
      prefs2 = resolver.resolve_for(other_meeting)

      expect(prefs1[:color_id]).to eq(5)
      expect(prefs2[:color_id]).to eq(7)
    end
  end

  describe "PREFERENCE_FIELDS constant" do
    it "includes all expected fields" do
      expected_fields = %i[
        title_template
        description_template
        location_template
        reminder_settings
        color_id
        visibility
      ]

      expect(PreferenceResolver::PREFERENCE_FIELDS).to match_array(expected_fields)
    end
  end

  describe "SYSTEM_DEFAULTS constant" do
    it "defines defaults for all preference fields" do
      expect(PreferenceResolver::SYSTEM_DEFAULTS).to include(
        :title_template,
        :description_template,
        :location_template,
        :reminder_settings,
        :color_id,
        :visibility
      )
    end

    it "has correct default templates" do
      expect(PreferenceResolver::SYSTEM_DEFAULTS[:title_template]).to eq("{{title}}")
      expect(PreferenceResolver::SYSTEM_DEFAULTS[:description_template]).to eq("{{faculty}}\n{{faculty_email}}")
      expect(PreferenceResolver::SYSTEM_DEFAULTS[:location_template]).to eq("{{building}} {{room}}")
    end

    it "has default reminder settings of 30 minutes" do
      reminders = PreferenceResolver::SYSTEM_DEFAULTS[:reminder_settings]

      expect(reminders).to be_an(Array)
      expect(reminders.first).to include("time" => "30", "type" => "minutes", "method" => "popup")
    end
  end

  describe "DND (Do Not Disturb) mode" do
    context "when notifications are disabled" do
      before do
        user.disable_notifications!
      end

      let(:dnd_resolver) { described_class.new(user) }

      it "returns empty reminder_settings regardless of system defaults" do
        prefs = dnd_resolver.resolve_for(meeting_time)

        expect(prefs[:reminder_settings]).to eq([])
        # Other preferences should still be resolved normally
        expect(prefs[:title_template]).to eq("{{title}}")
      end

      it "returns empty reminder_settings even when global preference is set" do
        create(:calendar_preference,
               user: user,
               scope: :global,
               reminder_settings: [{ "time" => "30", "type" => "minutes", "method" => "popup" }])

        prefs = dnd_resolver.resolve_for(meeting_time)

        expect(prefs[:reminder_settings]).to eq([])
      end

      it "returns empty reminder_settings even when event type preference is set" do
        create(:calendar_preference,
               user: user,
               scope: :event_type,
               event_type: "lecture",
               reminder_settings: [{ "time" => "45", "type" => "minutes", "method" => "popup" }])

        prefs = dnd_resolver.resolve_for(meeting_time)

        expect(prefs[:reminder_settings]).to eq([])
      end

      it "returns empty reminder_settings even when individual event preference is set" do
        create(:event_preference,
               user: user,
               preferenceable: meeting_time,
               reminder_settings: [{ "time" => "60", "type" => "minutes", "method" => "popup" }])

        prefs = dnd_resolver.resolve_for(meeting_time)

        expect(prefs[:reminder_settings]).to eq([])
      end
    end

    context "when notifications are enabled" do
      it "returns normal reminder_settings from system defaults" do
        prefs = resolver.resolve_for(meeting_time)

        expect(prefs[:reminder_settings]).to eq([{ "time" => "30", "type" => "minutes", "method" => "popup" }])
      end

      it "returns normal reminder_settings from preferences" do
        create(:calendar_preference,
               user: user,
               scope: :global,
               reminder_settings: [{ "time" => "15", "type" => "minutes", "method" => "popup" }])

        prefs = resolver.resolve_for(meeting_time)

        expect(prefs[:reminder_settings]).to eq([{ "time" => "15", "type" => "minutes", "method" => "popup" }])
      end
    end

    describe "#resolve_with_sources" do
      context "when notifications are disabled" do
        before do
          user.disable_notifications!
        end

        let(:dnd_resolver) { described_class.new(user) }

        it "returns actual reminder_settings for API display (ignores DND)" do
          result = dnd_resolver.resolve_with_sources(meeting_time)

          # resolve_with_sources ignores DND so the API can display what the user configured
          expect(result[:preferences][:reminder_settings]).to eq([{ "time" => "30", "type" => "minutes", "method" => "popup" }])
          expect(result[:sources][:reminder_settings]).to eq("system_default")
        end

        it "returns configured reminder_settings even when preferences are set" do
          create(:calendar_preference,
                 user: user,
                 scope: :global,
                 reminder_settings: [{ "time" => "45", "type" => "minutes", "method" => "popup" }])

          result = dnd_resolver.resolve_with_sources(meeting_time)

          # Should show the actual configured reminders, not empty due to DND
          expect(result[:preferences][:reminder_settings]).to eq([{ "time" => "45", "type" => "minutes", "method" => "popup" }])
          expect(result[:sources][:reminder_settings]).to eq("global")
        end
      end
    end

    describe "#notifications_disabled?" do
      it "returns false when notifications are enabled" do
        expect(resolver.notifications_disabled?).to be false
      end

      it "returns true when notifications are disabled" do
        user.disable_notifications!
        dnd_resolver = described_class.new(user)

        expect(dnd_resolver.notifications_disabled?).to be true
      end
    end

    describe "#resolve_actual_for" do
      context "when notifications are disabled" do
        before do
          user.disable_notifications!
        end

        let(:dnd_resolver) { described_class.new(user) }

        it "returns actual reminder_settings ignoring DND" do
          prefs = dnd_resolver.resolve_actual_for(meeting_time)

          expect(prefs[:reminder_settings]).to eq([{ "time" => "30", "type" => "minutes", "method" => "popup" }])
        end

        it "returns configured preferences when they exist" do
          create(:calendar_preference,
                 user: user,
                 scope: :global,
                 reminder_settings: [{ "time" => "15", "type" => "minutes", "method" => "popup" }])

          prefs = dnd_resolver.resolve_actual_for(meeting_time)

          expect(prefs[:reminder_settings]).to eq([{ "time" => "15", "type" => "minutes", "method" => "popup" }])
        end
      end

      context "when notifications are enabled" do
        it "behaves the same as resolve_for" do
          actual_prefs = resolver.resolve_actual_for(meeting_time)
          sync_prefs = resolver.resolve_for(meeting_time)

          expect(actual_prefs).to eq(sync_prefs)
        end
      end
    end
  end

  describe "university calendar events" do
    let(:uni_cal_event) do
      create(:university_calendar_event,
             summary: "Spring Break",
             category: "holiday",
             start_time: Time.zone.local(2025, 3, 10),
             end_time: Time.zone.local(2025, 3, 14))
    end

    context "with no preferences set" do
      it "returns university calendar defaults" do
        prefs = resolver.resolve_for(uni_cal_event)

        expect(prefs[:title_template]).to eq("{{summary}}")
        expect(prefs[:description_template]).to eq("{{description}}")
        expect(prefs[:location_template]).to eq("{{location}}")
        expect(prefs[:color_id]).to eq(8) # Graphite default
        expect(prefs[:visibility]).to eq("default")
      end
    end

    context "with uni_cal_category preference" do
      let!(:holiday_pref) do
        create(:calendar_preference,
               user: user,
               scope: :uni_cal_category,
               event_type: "holiday",
               color_id: 6,
               title_template: "🎉 {{summary}}")
      end

      it "uses uni_cal_category preference" do
        prefs = resolver.resolve_for(uni_cal_event)

        expect(prefs[:color_id]).to eq(6)
        expect(prefs[:title_template]).to eq("🎉 {{summary}}")
      end

      it "returns the correct source" do
        result = resolver.resolve_with_sources(uni_cal_event)

        expect(result[:sources][:color_id]).to eq("uni_cal_category:holiday")
        expect(result[:sources][:title_template]).to eq("uni_cal_category:holiday")
      end
    end

    context "with different categories" do
      let(:deadline_event) do
        create(:university_calendar_event,
               summary: "Registration Deadline",
               category: "deadline",
               start_time: Time.zone.local(2025, 4, 1),
               end_time: Time.zone.local(2025, 4, 1))
      end

      let!(:holiday_pref) do
        create(:calendar_preference,
               user: user,
               scope: :uni_cal_category,
               event_type: "holiday",
               color_id: 6)
      end

      let!(:deadline_pref) do
        create(:calendar_preference,
               user: user,
               scope: :uni_cal_category,
               event_type: "deadline",
               color_id: 11)
      end

      it "uses correct preference for each category" do
        holiday_prefs = resolver.resolve_for(uni_cal_event)
        deadline_prefs = resolver.resolve_for(deadline_event)

        expect(holiday_prefs[:color_id]).to eq(6)
        expect(deadline_prefs[:color_id]).to eq(11)
      end
    end

    context "with global preference but no category preference" do
      let!(:global_pref) do
        create(:calendar_preference,
               user: user,
               scope: :global,
               color_id: 3)
      end

      it "falls back to global preference" do
        prefs = resolver.resolve_for(uni_cal_event)

        expect(prefs[:color_id]).to eq(3)
      end
    end
  end
end

# frozen_string_literal: true

# A time of day as an HHMM integer: 1350 is 13:50 and 905 is 09:05. Banner
# sends times this way, and the meeting time and final exam columns store
# them this way. Plain arithmetic on the integer is wrong (09:45 to 10:00 is
# not 55 minutes), so read and write the value through this module.
module Hhmm
  # "9:05", "09:05", "9:05 PM", "905" or "0905".
  TEXT = /\A(?:(\d{1,2}):(\d{2})\s*(AM|PM)?|(\d{1,2})(\d{2}))\z/i

  module_function

  def minutes(hhmm) = ((hhmm / 100) * 60) + (hhmm % 100)

  def hours(hhmm) = minutes(hhmm) / 60.0

  # Whole minutes first, so 15:05 to 17:05 is exactly 2.0.
  def duration_hours(from, to) = (minutes(to) - minutes(from)) / 60.0

  def from_time(time) = (time.hour * 100) + time.min

  # "13:50".
  def format(hhmm) = Kernel.format("%02d:%02d", *hhmm.divmod(100))

  # "1:50 PM". With short: true, a whole hour drops its minutes: "1 PM".
  # 2400, the end of a day, is midnight.
  def format_12h(hhmm, short: false)
    hour, minute = hhmm.divmod(100)
    suffix = hour < 12 || hour == 24 ? "AM" : "PM"
    hour12 = ((hour - 1) % 12) + 1
    return "#{hour12} #{suffix}" if short && minute.zero?

    Kernel.format("%d:%02d %s", hour12, minute, suffix)
  end

  # The time on a date, in the zone.
  def on(date, hhmm, zone: Time.zone)
    hour, minute = hhmm.divmod(100)
    zone.local(date.year, date.month, date.day, hour, minute)
  end

  # The HHMM of a text in TEXT, or nil when it is not a time of day.
  def parse(value)
    match = value.to_s.strip.match(TEXT)
    return nil unless match

    hour   = (match[1] || match[4]).to_i
    minute = (match[2] || match[5]).to_i
    hour = (hour % 12) + (match[3].casecmp?("PM") ? 12 : 0) if match[3]
    return nil if hour > 23 || minute > 59

    (hour * 100) + minute
  end
end

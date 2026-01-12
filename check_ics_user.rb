# Find user by calendar token
user = User.find_by(calendar_token: "3bAD51jA546jrRFE4Ex553oH5awdljzSrIm2bd8qk6o")
if user
  puts "User: #{user.email}"
  config = user.user_extension_config
  if config
    puts "Sync university events: #{config.sync_university_events}"
    puts "Categories: #{config.university_event_categories.inspect}"
  else
    puts "No extension config"
  end
else
  puts "User not found"
end

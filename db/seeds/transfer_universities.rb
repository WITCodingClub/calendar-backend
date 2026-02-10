# frozen_string_literal: true

# Transfer Universities Seed Data
# This file creates sample transfer universities for development

Rails.logger.debug "Seeding transfer universities..."

# Massachusetts universities
umass = Transfer::University.find_or_create_by!(code: "UMASS") do |uni|
  uni.name = "University of Massachusetts"
  uni.state = "MA"
  uni.country = "USA"
  uni.active = true
end

mit = Transfer::University.find_or_create_by!(code: "MIT") do |uni|
  uni.name = "Massachusetts Institute of Technology"
  uni.state = "MA"
  uni.country = "USA"
  uni.active = true
end

bu = Transfer::University.find_or_create_by!(code: "BU") do |uni|
  uni.name = "Boston University"
  uni.state = "MA"
  uni.country = "USA"
  uni.active = true
end

# Other states
ucb = Transfer::University.find_or_create_by!(code: "UCB") do |uni|
  uni.name = "University of California, Berkeley"
  uni.state = "CA"
  uni.country = "USA"
  uni.active = true
end

# Community colleges
bhcc = Transfer::University.find_or_create_by!(code: "BHCC") do |uni|
  uni.name = "Bunker Hill Community College"
  uni.state = "MA"
  uni.country = "USA"
  uni.active = true
end

Rails.logger.debug { "Created #{Transfer::University.count} transfer universities" }

# Create some sample transfer courses
Rails.logger.debug "Creating sample transfer courses..."

# UMass courses
umass_cs101 = Transfer::Course.find_or_create_by!(university: umass, course_code: "CS101") do |course|
  course.course_title = "Introduction to Computer Science"
  course.credits = 3.0
  course.description = "Fundamental concepts of computer science and programming"
  course.active = true
end

umass_cs201 = Transfer::Course.find_or_create_by!(university: umass, course_code: "CS201") do |course|
  course.course_title = "Data Structures"
  course.credits = 3.0
  course.description = "Implementation and analysis of fundamental data structures"
  course.active = true
end

# MIT courses
# rubocop:disable Naming/VariableNumber
mit_6001 = Transfer::Course.find_or_create_by!(university: mit, course_code: "6.001") do |course|
  # rubocop:enable Naming/VariableNumber
  course.course_title = "Structure and Interpretation of Computer Programs"
  course.credits = 12.0
  course.description = "Introduction to computation"
  course.active = true
end

Rails.logger.debug { "Created #{Transfer::Course.count} transfer courses" }

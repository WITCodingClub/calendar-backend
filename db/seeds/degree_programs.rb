# frozen_string_literal: true

# Degree Programs Seed Data
# This file creates sample degree programs for development

Rails.logger.debug "Seeding degree programs..."

# Computer Science programs
cs_undergrad = DegreeProgram.find_or_create_by!(program_code: "BCOS3") do |program|
  program.leopardweb_code = "P202620"
  program.program_name = "Computer Science"
  program.degree_type = "Bachelor of Science"
  program.level = "Undergraduate"
  program.college = "College of Engineering and Sciences"
  program.department = "Computer Science"
  program.catalog_year = 2026
  program.credit_hours_required = 120.0
  program.minimum_gpa = 2.0
  program.active = true
end

cs_graduate = DegreeProgram.find_or_create_by!(program_code: "MCOS3") do |program|
  program.leopardweb_code = "P202621"
  program.program_name = "Computer Science (M.S.)"
  program.degree_type = "Master of Science"
  program.level = "Graduate"
  program.college = "College of Engineering and Sciences"
  program.department = "Computer Science"
  program.catalog_year = 2026
  program.credit_hours_required = 30.0
  program.minimum_gpa = 3.0
  program.active = true
end

# Engineering programs
mech_eng = DegreeProgram.find_or_create_by!(program_code: "BEME3") do |program|
  program.leopardweb_code = "P202622"
  program.program_name = "Mechanical Engineering"
  program.degree_type = "Bachelor of Science"
  program.level = "Undergraduate"
  program.college = "College of Engineering and Sciences"
  program.department = "Engineering"
  program.catalog_year = 2026
  program.credit_hours_required = 128.0
  program.minimum_gpa = 2.0
  program.active = true
end

# Business programs
business_admin = DegreeProgram.find_or_create_by!(program_code: "BBAD3") do |program|
  program.leopardweb_code = "P202623"
  program.program_name = "Business Administration"
  program.degree_type = "Bachelor of Science"
  program.level = "Undergraduate"
  program.college = "College of Business"
  program.department = "Business Administration"
  program.catalog_year = 2026
  program.credit_hours_required = 120.0
  program.minimum_gpa = 2.0
  program.active = true
end

# Minors
cs_minor = DegreeProgram.find_or_create_by!(program_code: "MNCS3") do |program|
  program.leopardweb_code = "P202624"
  program.program_name = "Computer Science Minor"
  program.degree_type = "Minor"
  program.level = "Undergraduate"
  program.college = "College of Engineering and Sciences"
  program.department = "Computer Science"
  program.catalog_year = 2026
  program.credit_hours_required = 18.0
  program.minimum_gpa = 2.0
  program.active = true
end

Rails.logger.debug { "Created #{DegreeProgram.count} degree programs" }

# Create some degree requirements for CS program
Rails.logger.debug "Creating degree requirements for Computer Science..."

# Core requirements
core_area = DegreeRequirement.find_or_create_by!(
  degree_program: cs_undergrad,
  area_name: "Core Requirements",
  requirement_name: "Programming Fundamentals"
) do |req|
  req.requirement_type = "core"
  req.credits_required = 3.0
  req.courses_required = 1
  req.subject = "COMP"
  req.course_number = 1000
  req.rule_text = "Complete COMP1000 - Introduction to Programming"
end

DegreeRequirement.find_or_create_by!(
  degree_program: cs_undergrad,
  area_name: "Core Requirements",
  requirement_name: "Data Structures"
) do |req|
  req.requirement_type = "core"
  req.credits_required = 3.0
  req.courses_required = 1
  req.subject = "COMP"
  req.course_number = 2000
  req.rule_text = "Complete COMP2000 - Data Structures"
end

# Math requirements
DegreeRequirement.find_or_create_by!(
  degree_program: cs_undergrad,
  area_name: "Mathematics",
  requirement_name: "Calculus I"
) do |req|
  req.requirement_type = "core"
  req.credits_required = 4.0
  req.courses_required = 1
  req.subject = "MATH"
  req.course_number = 1777
  req.rule_text = "Complete MATH1777 - Calculus I"
end

# Electives
DegreeRequirement.find_or_create_by!(
  degree_program: cs_undergrad,
  area_name: "CS Electives",
  requirement_name: "Computer Science Electives"
) do |req|
  req.requirement_type = "elective"
  req.credits_required = 12.0
  req.courses_required = 4
  req.rule_text = "Complete 12 credits of 3000+ level COMP courses"
  req.course_choice_logic = "any"
end

Rails.logger.debug { "Created #{DegreeRequirement.count} degree requirements" }

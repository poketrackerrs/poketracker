#!/usr/bin/env ruby
# Embed (Copy Files → Frameworks, Code Sign On Copy) every *.framework in
# ios/Frameworks/ into the Runner target, and add ios/Frameworks to the
# framework search paths. dlopen-only: we do NOT link against them.
# Idempotent — re-running won't duplicate refs.
require 'xcodeproj'

root = File.expand_path(File.dirname(__FILE__))
proj_path = File.join(root, 'Runner.xcodeproj')
fw_dir = File.join(root, 'Frameworks')
project = Xcodeproj::Project.open(proj_path)
target = project.targets.find { |t| t.name == 'Runner' }
abort 'Runner target not found' unless target

frameworks = Dir.glob(File.join(fw_dir, '*.framework')).sort
abort 'no frameworks in ios/Frameworks' if frameworks.empty?

# A dedicated Copy Files phase (Frameworks dest) so we don't disturb Flutter's.
phase = target.copy_files_build_phases.find { |p| p.name == 'Embed Core Frameworks' }
unless phase
  phase = target.new_copy_files_build_phase('Embed Core Frameworks')
  phase.symbol_dst_subfolder_spec = :frameworks
end

# Group to hold the file references.
group = project.main_group.find_subpath('Frameworks', true)

frameworks.each do |fw|
  name = File.basename(fw)
  ref = group.files.find { |f| f.path && File.basename(f.path) == name }
  ref ||= group.new_reference(fw)
  # Skip if already in the embed phase.
  next if phase.files_references.include?(ref)
  bf = phase.add_file_reference(ref, true)
  bf.settings = { 'ATTRIBUTES' => ['CodeSignOnCopy', 'RemoveHeadersOnCopy'] }
  puts "embedding #{name}"
end

# Move our copy phase BEFORE Flutter's "Thin Binary" script phase, else Xcode
# reports "Cycle inside Runner" (the app codesign/thin depends on frameworks
# being in place, but our copy ran after it).
thin_idx = target.build_phases.index { |p| p.respond_to?(:name) && p.name == 'Thin Binary' }
cur_idx = target.build_phases.index(phase)
if thin_idx && cur_idx && cur_idx > thin_idx
  target.build_phases.delete(phase)
  target.build_phases.insert(thin_idx, phase)
  puts 'reordered Embed Core Frameworks before Thin Binary'
end

# Framework search path so the linker/loader can find them.
target.build_configurations.each do |cfg|
  paths = cfg.build_settings['FRAMEWORK_SEARCH_PATHS'] || ['$(inherited)']
  paths = [paths] unless paths.is_a?(Array)
  sp = '$(PROJECT_DIR)/Frameworks'
  paths << sp unless paths.include?(sp)
  cfg.build_settings['FRAMEWORK_SEARCH_PATHS'] = paths
end

project.save
puts "saved #{proj_path}"

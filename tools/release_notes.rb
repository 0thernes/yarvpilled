#!/usr/bin/env ruby
# frozen_string_literal: true

# Prints the CHANGELOG.md section for one version: the release notes the Release workflow publishes.
#   ruby tools/release_notes.rb 0.4.1 [CHANGELOG.md]
# The section ends at the next "## [" heading or at the link definitions ("[x.y.z]: https://...").
# A body line that merely starts with a Markdown link does not end it.

module ReleaseNotes
  def self.extract(changelog, version)
    changelog[/^## \[#{Regexp.escape(version)}\][^\n]*\n(.*?)(?=^## \[|^\[[^\]\n]+\]: |\z)/m, 1]&.strip
  end
end

if $PROGRAM_NAME == __FILE__
  version = ARGV.fetch(0) { abort "usage: release_notes.rb VERSION [CHANGELOG.md]" }
  body = ReleaseNotes.extract(File.read(ARGV.fetch(1, File.join(__dir__, "..", "CHANGELOG.md"))), version)
  abort "no CHANGELOG entry for #{version}" if body.nil? || body.empty?
  puts body
end

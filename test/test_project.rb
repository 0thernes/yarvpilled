# frozen_string_literal: true

require_relative "test_helper"

# Release hygiene: the version is stated in one place per format and they agree.
class TestProject < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_version_file_matches_constant
    assert_equal Yarvpilled::VERSION, File.read(File.join(ROOT, "VERSION")).strip
  end

  def test_changelog_and_citation_mention_current_version
    assert_match(/^## \[#{Regexp.escape(Yarvpilled::VERSION)}\] - \d{4}-\d{2}-\d{2}$/,
                 File.read(File.join(ROOT, "CHANGELOG.md")))
    assert_match(/^version: "#{Regexp.escape(Yarvpilled::VERSION)}"$/, File.read(File.join(ROOT, "CITATION.cff")))
  end

  def test_readme_citation_and_lean_package_carry_the_version
    v = Regexp.escape(Yarvpilled::VERSION)
    assert_match(/^  version = \{#{v}\},$/, File.read(File.join(ROOT, "README.md")), "README BibTeX version")
    assert_match(/^version = "#{v}"$/, File.read(File.join(ROOT, "formal/lean/lakefile.toml")), "Lean package version")
  end

  def test_yaml_and_json_files_parse
    require "yaml"
    require "json"
    # An unquoted "label: Optional: ..." once made the replication issue form invalid YAML,
    # which GitHub hides instead of reporting.
    Dir.glob("{.github/**/*.yml,CITATION.cff}", base: ROOT).each do |f|
      YAML.safe_load_file(File.join(ROOT, f))
    rescue Psych::SyntaxError => e
      flunk "#{f}: #{e.message}"
    end
    Dir.glob("{docs,bench}/**/*.json", base: ROOT).each do |f|
      JSON.parse(File.read(File.join(ROOT, f)))
    rescue JSON::ParserError => e
      flunk "#{f}: #{e.message}"
    end
  end

  def test_native_energy_uses_all_64_bits
    skip "native extension not built" unless Yarvpilled::Native::AVAILABLE
    # Windows uses LLP64: C long is 32 bits even on x86-64. NUM2LONG/LONG2NUM silently
    # narrowed int64 energy in snapshot/split (or rejected it at spawn/feed).
    w = Yarvpilled::Native::World.new(160, 160, 8, 8, :c)
    slot = w.spawn(10.0, 10.0, 0, 1 << 40, 1, 1)
    assert_equal 1 << 40, w.snapshot[4]
    w.feed(slot, 1 << 40)
    assert_equal 1 << 41, w.snapshot[4]
    assert_equal (1 << 40) - 20, w.split(slot)
    assert_equal 1 << 40, w.snapshot[4]
  end

  def test_release_notes_cover_each_whole_changelog_section
    require_relative "../tools/release_notes"
    log = File.read(File.join(ROOT, "CHANGELOG.md"))
    versions = log.scan(/^## \[(\d+\.\d+\.\d+)\]/).flatten
    refute_empty versions
    versions.each do |v|
      body = ReleaseNotes.extract(log, v)
      section = log[/^## \[#{Regexp.escape(v)}\][^\n]*\n(.*?)(?=^## \[|^\[\d|^\[Unreleased\]:|\z)/m, 1].strip
      # v0.4.0 shipped with its notes cut at a body line starting with "[docs/...](...)".
      assert_equal section, body, "release notes for #{v} must be the whole section"
    end
  end

  def test_semver
    assert_match(/\A\d+\.\d+\.\d+\z/, Yarvpilled::VERSION)
  end

  def test_pure_ruby_world_always_available
    assert Yarvpilled::World.available?(:ruby)
  end
end

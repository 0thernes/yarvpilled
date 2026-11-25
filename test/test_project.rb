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

  def test_semver
    assert_match(/\A\d+\.\d+\.\d+\z/, Yarvpilled::VERSION)
  end

  def test_pure_ruby_world_always_available
    assert Yarvpilled::World.available?(:ruby)
  end
end

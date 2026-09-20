#!/usr/bin/env ruby

# Choose by semantic version, not release creation date: backfills must not
# accidentally compare an older version against the newest published release.
def previous_release_tag(tag, tags)
  version = tag.match(/\A(\d+)\.(\d+)\.(\d+)\z/)
  abort "Release tag must use MAJOR.MINOR.PATCH format" unless version
  target = version.captures.map(&:to_i)
  candidates = tags.map do |candidate|
    match = candidate.match(/\A(\d+)\.(\d+)\.(\d+)\z/)
    next unless match
    numbers = match.captures.map(&:to_i)
    [numbers, candidate] if (numbers <=> target) == -1
  end.compact
  candidates.max_by(&:first)&.last
end

if $PROGRAM_NAME == __FILE__
  require "open3"
  tags, status = Open3.capture2("git", "tag", "--list")
  abort "Unable to list release tags" unless status.success?
  puts previous_release_tag(ARGV.fetch(0), tags.lines.map(&:strip))
end

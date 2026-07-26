# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "mr_shell"

codec = MrShell::Codecs::TSV.new
registry = MrShell::ReducerRegistry.default

phrases = MrShell::Pipeline.from_lines(ARGF, codec)
words = phrases.flat_map do |record|
  record.key.split.map do |word|
    MrShell::Record.new(word, record.values)
  end
end

counts = words
  .sort_by_key
  .reduce_by_key(registry.parse("sum"))

counts.each { |record| puts codec.dump(record) }

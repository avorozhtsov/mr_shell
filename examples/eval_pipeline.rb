# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "mr_shell"

records = [
  MrShell::Record.new("red blue", [2]),
  MrShell::Record.new("blue", [1])
]

evaluator = MrShell::RubyEvaluator.new
registry = MrShell::ReducerRegistry.default

pipeline = evaluator.flat_map(
  MrShell::Pipeline.new(records),
  "key.split.map { |word| [word, value] }"
)
pipeline = pipeline
  .sort_by_key
  .reduce_by_key(registry.parse("sum"))

puts pipeline.explain
pipeline.each { |record| p record.to_a }

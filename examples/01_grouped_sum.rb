# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "mr_shell"

records = [
  MrShell::Record.new("a", [1]),
  MrShell::Record.new("a", [2]),
  MrShell::Record.new("b", [3])
]

registry = MrShell::ReducerRegistry.default
pipeline = MrShell::Pipeline.new(records)
  .reduce_by_key(registry.parse("sum"))

puts pipeline.explain
pipeline.each { |record| p record.to_a }

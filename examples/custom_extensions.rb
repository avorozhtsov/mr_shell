# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "stringio"
require "mr_shell"

class ScaleValues < MrShell::Stages::Base
  def initialize(factor)
    @factor = factor
    super("ScaleValues(#{factor})")
  end

  def call(input)
    stream do |output|
      input.each do |record|
        output << MrShell::Record.new(record.key, [record.value * @factor])
      end
    end
  end
end

framework = MrShell::Framework.default

framework.codecs.register("pipe") do |**_options|
  MrShell::Codecs::TSV.new(input_separator: "|", output_separator: "|")
end
framework.reducers.register(
  "sum_squares",
  initial: -> { 0 },
  step: ->(total, value) { total + (value * value) },
  finalize: ->(total) { total }
)
framework.stages.register("scale") do |factor:|
  ScaleValues.new(factor)
end

codec = framework.codecs.build("pipe")
reducer = framework.reducers.fetch("sum_squares")
stage = framework.stages.build("scale", factor: 10)

MrShell::Contracts.verify_codec(
  codec,
  records: [MrShell::Record.new("a", [2])]
)
MrShell::Contracts.verify_reducer(reducer, values: [2, 3])
MrShell::Contracts.verify_stage(
  stage,
  input: [MrShell::Record.new("a", [2])]
)

pipeline = MrShell::Pipeline.from_lines(StringIO.new("a|2\na|3\n"), codec)
  .add_stage(stage)
  .reduce_by_key(framework.reducers.parse("sum_squares"))

puts pipeline.explain
pipeline.each { |record| puts codec.dump(record) }

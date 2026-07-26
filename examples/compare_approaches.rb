# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "mr_shell"

module MrShellExamples
  # Three implementations of the same group-and-sum operation. Keeping them
  # together makes the framework's extra machinery and benefits easy to see.
  module CompareApproaches
    module_function

    def eager(records)
      records
        .group_by(&:key)
        .map do |key, group|
          MrShell::Record.new(key, [group.sum(&:value)])
        end
        .sort_by(&:key)
    end

    def standard_library(records)
      records
        .sort_by(&:key)
        .slice_when { |left, right| left.key != right.key }
        .lazy
        .map do |group|
          MrShell::Record.new(group.first.key, [group.sum(&:value)])
        end
    end

    def framework(records, registry: MrShell::ReducerRegistry.default)
      MrShell::Pipeline.new(records)
        .sort_by_key
        .reduce_by_key(registry.parse("sum"))
    end

    def unix_sort(records, registry: MrShell::ReducerRegistry.default)
      MrShell::Pipeline.new(records)
        .through(["sort"], codec: MrShell::Codecs::JSONLines.new)
        .reduce_by_key(registry.parse("sum"))
    end

    def records(size)
      random = Random.new(12_345)
      Array.new(size) do
        key = format("key-%03d", random.rand(100))
        MrShell::Record.new(key, [random.rand(1..10)])
      end
    end

    def verify(records)
      comparison(records).verify!
    end

    def run(size: 100_000, output: $stdout)
      input = records(size)
      output.puts("Comparing group-and-sum for #{size} records.")
      comparison(input).report(output: output)
    end

    def comparison(records)
      MrShell::Comparison.new
        .add("eager group_by") { eager(records) }
        .add("Enumerator::Lazy") { standard_library(records) }
        .add("MrShell::Pipeline") { framework(records) }
        .add("Unix sort + MrShell") { unix_sort(records) }
    end
  end
end

if $PROGRAM_NAME == __FILE__
  size = Integer(ENV.fetch("SIZE", "100000"), 10)
  MrShellExamples::CompareApproaches.run(size: size)
end

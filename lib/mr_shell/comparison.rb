# frozen_string_literal: true

require "objspace"

module MrShell
  # Correctness comes before timing: report refuses to benchmark approaches
  # that produce different materialized results.
  class Comparison
    Measurement = Struct.new(
      :name,
      :items,
      :total_seconds,
      :first_seconds,
      :allocations,
      :peak_heap_bytes
    )

    def initialize
      @approaches = []
    end

    def add(name, &approach)
      raise ConfigurationError, "Comparison approach requires a block" unless approach

      @approaches << [name, approach]
      self
    end

    def verify!
      raise ContractError, "Comparison requires at least two approaches" if @approaches.length < 2

      expected_name, expected = materialized(@approaches.first)
      @approaches.drop(1).each do |approach|
        name, actual = materialized(approach)
        next if actual == expected

        raise ContractError,
              "#{name} disagrees with #{expected_name}: " \
              "#{actual.inspect} != #{expected.inspect}"
      end
      expected
    end

    def measurements
      verify!
      @approaches.map { |name, approach| measure(name, approach) }
    end

    def report(output: $stdout)
      results = measurements
      output.puts("All #{results.length} approaches produced the same result.")
      output.puts
      output.puts(
        format(
          "%<name>-22s %<items>8s %<total>10s %<first>10s %<allocations>12s %<peak>12s",
          name: "approach",
          items: "items",
          total: "total ms",
          first: "first ms",
          allocations: "allocations",
          peak: "peak KiB"
        )
      )
      results.each do |measurement|
        output.puts(
          format(
            "%<name>-22s %<items>8d %<total>10.3f %<first>10.3f " \
            "%<allocations>12d %<peak>12.1f",
            name: measurement.name,
            items: measurement.items,
            total: measurement.total_seconds * 1_000,
            first: measurement.first_seconds * 1_000,
            allocations: measurement.allocations,
            peak: measurement.peak_heap_bytes / 1_024.0
          )
        )
      end
      results
    end

    private

    def materialized(approach)
      name, function = approach
      [name, consume(function.call).first]
    end

    def measure(name, approach)
      GC.start
      allocations_before = GC.stat(:total_allocated_objects)
      baseline_heap = ObjectSpace.memsize_of_all
      peak_heap = baseline_heap
      sampling = true
      sampler = Thread.new do
        while sampling
          peak_heap = [peak_heap, ObjectSpace.memsize_of_all].max
          sleep(0.01)
        end
      end
      sampler.report_on_exception = false if sampler.respond_to?(:report_on_exception=)

      started = monotonic_time
      value = approach.call
      result, first_seconds = consume(value, started: started)
      finished = monotonic_time
      sampling = false
      sampler.join
      peak_heap = [peak_heap, ObjectSpace.memsize_of_all].max

      Measurement.new(
        name,
        result.length,
        finished - started,
        first_seconds,
        GC.stat(:total_allocated_objects) - allocations_before,
        [peak_heap - baseline_heap, 0].max
      )
    ensure
      sampling = false
      sampler&.join
    end

    def consume(value, started: nil)
      unless value.respond_to?(:each)
        raise ContractError, "Comparison approach must return an enumerable"
      end

      result = []
      first_seconds = nil
      value.each do |item|
        first_seconds ||= monotonic_time - started if started
        result << item
      end
      first_seconds ||= monotonic_time - started if started
      [result, first_seconds]
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end

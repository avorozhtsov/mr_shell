# frozen_string_literal: true

require_relative "test_helper"

class ReducerRegistryTest < Minitest::Test
  def setup
    @registry = MrShell::ReducerRegistry.default
  end

  def test_parses_multiple_reducers_and_aliases
    specs = @registry.parse("sum[0];sigma[1],count")

    assert_equal %w[sum stddev count], specs.map(&:name)
    assert_equal [0, 1, nil], specs.map(&:field)
  end

  def test_rejects_unknown_or_malformed_reducers
    assert_raises(MrShell::ConfigurationError) { @registry.parse("missing") }
    assert_raises(MrShell::ConfigurationError) { @registry.parse("sum[x]") }
    assert_raises(MrShell::ConfigurationError) { @registry.parse("") }
  end

  def test_count_rejects_a_field_selector
    assert_raises(MrShell::ConfigurationError) { @registry.parse("count[0]") }
  end

  def test_numeric_and_collection_reducers
    result = reduce(
      [1, 2, 2, 5],
      "sum;prod;min;max;count;avg;stddev;relative_stddev;collect;uniq;frequency"
    )

    assert_equal 10, result.values[0]
    assert_equal 20, result.values[1]
    assert_equal 1, result.values[2]
    assert_equal 5, result.values[3]
    assert_equal 4, result.values[4]
    assert_in_delta 2.5, result.values[5]
    assert_in_delta Math.sqrt(2.25), result.values[6]
    assert_in_delta 0.6, result.values[7]
    assert_equal [1, 2, 2, 5], result.values[8]
    assert_equal [1, 2, 5], result.values[9]
    assert_equal({ 1 => 1, 2 => 2, 5 => 1 }, result.values[10])
  end

  def test_multivalue_record_requires_a_field
    records = [MrShell::Record.new("a", [1, 2])]
    pipeline = MrShell::Pipeline.new(records)

    error = assert_raises(MrShell::DataError) do
      pipeline.reduce_by_key(@registry.parse("sum")).to_a
    end
    assert_match(/needs a field selector/, error.message)
  end

  def test_framework_can_be_extended_with_a_custom_reducer
    registry = MrShell::ReducerRegistry.new
    registry.register(
      "words",
      initial: -> { [] },
      step: ->(accumulator, value) { accumulator + [value.upcase] },
      finalize: ->(accumulator) { accumulator.join("-") }
    )
    records = [
      MrShell::Record.new("a", ["one"]),
      MrShell::Record.new("a", ["two"])
    ]

    result = MrShell::Pipeline.new(records)
      .reduce_by_key(registry.parse("words"))
      .to_a

    assert_equal [MrShell::Record.new("a", ["ONE-TWO"])], result
  end

  private

  def reduce(values, description)
    records = values.map { |value| MrShell::Record.new("key", [value]) }
    MrShell::Pipeline.new(records)
      .reduce_by_key(@registry.parse(description))
      .to_a
      .fetch(0)
  end
end

# frozen_string_literal: true

require_relative "test_helper"

class PipelineTest < Minitest::Test
  def setup
    @registry = MrShell::ReducerRegistry.default
  end

  def test_lazy_mapping_filtering_and_flat_mapping
    touched = []
    source = [
      MrShell::Record.new("one two", [1]),
      MrShell::Record.new("three", [2])
    ]
    pipeline = MrShell::Pipeline.new(source)
      .map do |record|
        touched << record.key
        record
      end
      .filter { |record| record.values.first.odd? }
      .flat_map do |record|
        record.key.split.map { |word| MrShell::Record.new(word, record.values) }
      end

    assert_empty touched
    assert_equal %w[one two], pipeline.to_a.map(&:key)
    assert_equal ["one two", "three"], touched
  end

  def test_reduce_by_key_handles_empty_input
    result = MrShell::Pipeline.new([])
      .reduce_by_key(@registry.parse("sum"))
      .to_a

    assert_empty result
  end

  def test_reduce_by_key_emits_one_record_per_adjacent_group
    records = [
      MrShell::Record.new("a", [1]),
      MrShell::Record.new("a", [2]),
      MrShell::Record.new("b", [3])
    ]

    assert_equal(
      [MrShell::Record.new("a", [3]), MrShell::Record.new("b", [3])],
      MrShell::Pipeline.new(records)
        .reduce_by_key(@registry.parse("sum"))
        .to_a
    )
  end

  def test_sorted_verification_rejects_decreasing_keys
    records = [
      MrShell::Record.new("b", [1]),
      MrShell::Record.new("a", [2])
    ]

    error = assert_raises(MrShell::DataError) do
      MrShell::Pipeline.new(records)
        .reduce_by_key(@registry.parse("sum"), verify_sorted: true)
        .to_a
    end
    assert_match(/not sorted/, error.message)
  end

  def test_sort_by_key_is_an_explicit_in_memory_stage
    records = [
      MrShell::Record.new("b", [1]),
      MrShell::Record.new("a", [2])
    ]

    assert_equal %w[a b], MrShell::Pipeline.new(records).sort_by_key.to_a.map(&:key)
  end

  def test_uniq_by_preserves_first_seen_order
    records = [1, 2, 1, 3].map { |value| MrShell::Record.new(value, []) }

    result = MrShell::Pipeline.new(records).uniq_by(&:key).to_a

    assert_equal [1, 2, 3], result.map(&:key)
  end

  def test_randomized_reduction_matches_group_by
    random = Random.new(12_345)

    50.times do
      pairs = Array.new(random.rand(0..100)) do
        [random.rand(0..9), random.rand(-100..100)]
      end
      records = pairs.sort_by(&:first).map do |key, value|
        MrShell::Record.new(key, [value])
      end
      expected = pairs.group_by(&:first).sort.to_h.transform_values do |group|
        group.sum(&:last)
      end
      actual = MrShell::Pipeline.new(records)
        .reduce_by_key(@registry.parse("sum"), verify_sorted: true)
        .to_a
        .to_h { |record| [record.key, record.value] }

      assert_equal expected, actual
    end
  end

  def test_library_does_not_replace_rubys_reduce
    assert_equal 6, [1, 2, 3].reduce(:+)
  end

  def test_explain_makes_the_plan_visible_without_running_it
    touched = false
    pipeline = MrShell::Pipeline.new([], source_name: "Input(Test)")
      .map(label: "Double") do |record|
        touched = true
        record
      end
      .filter(label: "Positive") { |record| record.value.positive? }
      .reduce_by_key(@registry.parse("sum"))

    assert_equal(
      [
        "Input(Test)",
        "→ Double",
        "→ Positive",
        "→ ReduceByKey(sum)"
      ].join("\n"),
      pipeline.explain
    )
    refute touched
  end

  def test_lazy_failure_identifies_the_stage
    pipeline = MrShell::Pipeline.new([MrShell::Record.new("a", [1])])
      .map(label: "Broken arithmetic") { |record| record.value.public_send(:+, "x") }

    error = assert_raises(MrShell::StageError) { pipeline.to_a }
    assert_equal "Broken arithmetic", error.stage
    assert_instance_of TypeError, error.original
  end
end

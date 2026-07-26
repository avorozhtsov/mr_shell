# frozen_string_literal: true

require_relative "test_helper"

class PipelineLawsTest < Minitest::Test
  def setup
    @records = [
      MrShell::Record.new("a", [1]),
      MrShell::Record.new("b", [2])
    ]
  end

  def test_mapping_identity_preserves_input
    result = MrShell::Pipeline.new(@records).map { |record| record }.to_a

    assert_equal @records, result
  end

  def test_filtering_with_true_preserves_input
    result = MrShell::Pipeline.new(@records).filter { true }.to_a

    assert_equal @records, result
  end

  def test_adding_a_stage_does_not_mutate_the_previous_pipeline
    original = MrShell::Pipeline.new(@records)
    extended = original.map { |record| record }

    assert_empty original.stages
    assert_equal 1, extended.stages.length
    assert_equal @records, original.to_a
  end

  def test_flat_map_with_singleton_is_equivalent_to_map
    mapped = MrShell::Pipeline.new(@records)
      .map { |record| MrShell::Record.new(record.key, [record.value * 2]) }
      .to_a
    flat_mapped = MrShell::Pipeline.new(@records)
      .flat_map { |record| [MrShell::Record.new(record.key, [record.value * 2])] }
      .to_a

    assert_equal mapped, flat_mapped
  end
end

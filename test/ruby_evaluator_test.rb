# frozen_string_literal: true

require_relative "test_helper"

class RubyEvaluatorTest < Minitest::Test
  def setup
    @evaluator = MrShell::RubyEvaluator.new
    @pipeline = MrShell::Pipeline.new(
      [
        MrShell::Record.new("red blue", [2]),
        MrShell::Record.new("blue", [1])
      ]
    )
  end

  def test_compile_exposes_readable_record_locals
    function = @evaluator.compile("[key.upcase, value * 2, values.length, record.class.name]")

    assert_equal(
      ["RED BLUE", 4, 1, "MrShell::Record"],
      function.call(@pipeline.first)
    )
  end

  def test_map_and_filter_build_lazy_pipeline_stages
    result = @evaluator
      .map(@pipeline, "[key.upcase, value * 2]")
      .then { |pipeline| @evaluator.filter(pipeline, "value > 2") }
      .to_a

    assert_equal [MrShell::Record.new("RED BLUE", [4])], result
  end

  def test_flat_map_can_express_word_count_mapping
    result = @evaluator
      .flat_map(@pipeline, "key.split.map { |word| [word, value] }")
      .to_a

    assert_equal(
      [
        MrShell::Record.new("red", [2]),
        MrShell::Record.new("blue", [2]),
        MrShell::Record.new("blue", [1])
      ],
      result
    )
  end

  def test_full_eval_can_compose_framework_objects
    result = @evaluator.apply(
      MrShell::Pipeline.new(
        [
          MrShell::Record.new("a", [1]),
          MrShell::Record.new("a", [2])
        ]
      ),
      'pipeline.reduce_by_key(registry.parse("sum"))'
    )

    assert_equal [MrShell::Record.new("a", [3])], result.to_a
  end

  def test_compile_and_runtime_errors_are_framework_errors
    assert_raises(MrShell::EvaluationError) { @evaluator.compile("key.") }

    pipeline = @evaluator.map(@pipeline, "missing_method")
    error = assert_raises(MrShell::StageError) { pipeline.to_a }
    assert_instance_of MrShell::EvaluationError, error.original
    assert_match(/Map\(Ruby: missing_method\) failed/, error.message)
    assert_match(/NameError/, error.message)
  end
end

# frozen_string_literal: true

require_relative "test_helper"

class ExamplesTest < Minitest::Test
  EXAMPLES = File.expand_path("../examples", __dir__)

  def test_grouped_sum_example
    output = run_example("01_grouped_sum.rb")

    assert_match(/ReduceByKey\(sum\)/, output)
    assert_match(/\["a", 3\]/, output)
    assert_match(/\["b", 3\]/, output)
  end

  def test_eval_pipeline_example
    output = run_example("eval_pipeline.rb")

    assert_match(/FlatMap\(Ruby:/, output)
    assert_match(/\["blue", 3\]/, output)
    assert_match(/\["red", 2\]/, output)
  end

  def test_custom_extensions_example
    output = run_example("custom_extensions.rb")

    assert_match(/Input\(TSV\)/, output)
    assert_match(/ScaleValues\(10\)/, output)
    assert_match(/ReduceByKey\(sum_squares\)/, output)
    assert_match(/^a\|1300$/, output)
  end

  private

  def run_example(name)
    output, error, status = Open3.capture3(
      RbConfig.ruby,
      File.join(EXAMPLES, name)
    )
    assert status.success?, error
    output
  end
end

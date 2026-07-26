# frozen_string_literal: true

require_relative "test_helper"
require_relative "../examples/compare_approaches"
require_relative "../examples/compare_eval"

class ApproachesTest < Minitest::Test
  def test_eager_enumerable_and_framework_reducers_agree
    records = MrShellExamples::CompareApproaches.records(1_000)
    expected = MrShellExamples::CompareApproaches.eager(records)

    assert_equal expected, MrShellExamples::CompareApproaches.standard_library(records).to_a
    assert_equal expected, MrShellExamples::CompareApproaches.framework(records).to_a
    assert_equal expected, MrShellExamples::CompareApproaches.unix_sort(records).to_a
  end

  def test_direct_compiled_and_repeated_eval_agree
    records = Array.new(100) do |index|
      MrShell::Record.new("key-#{index}", [index])
    end
    expected = MrShellExamples::CompareEval.direct(records)

    assert_equal expected, MrShellExamples::CompareEval.compiled(records)
    assert_equal expected, MrShellExamples::CompareEval.evaluated_each_time(records)
    assert_equal expected, MrShellExamples::CompareEval.context(records)
    assert_equal expected, MrShellExamples::CompareEval.parsed(records)
  end
end

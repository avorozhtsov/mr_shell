# frozen_string_literal: true

require_relative "test_helper"

class RecordTest < Minitest::Test
  def test_record_exposes_key_values_and_scalar_value
    record = MrShell::Record.new("key", [1])

    assert_equal "key", record.key
    assert_equal [1], record.values
    assert_equal 1, record.value
    assert_equal ["key", 1], record.to_a
  end

  def test_record_with_multiple_values_returns_the_array
    record = MrShell::Record.new("key", [1, 2])

    assert_equal [1, 2], record.value
  end

  def test_record_is_immutable_and_has_value_semantics
    values = [1]
    record = MrShell::Record.new("key", values)
    values << 2

    assert_equal MrShell::Record.new("key", [1]), record
    assert record.frozen?
    assert record.values.frozen?
  end
end

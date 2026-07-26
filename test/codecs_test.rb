# frozen_string_literal: true

require_relative "test_helper"

class CodecsTest < Minitest::Test
  def test_tsv_auto_converts_strict_scalars
    codec = MrShell::Codecs::TSV.new
    record = codec.load("-3\t1.\t.5\t1e3\ttrue\tnull\tplain\n")

    assert_equal(-3, record.key)
    assert_equal [1.0, 0.5, 1000.0, true, nil, "plain"], record.values
  end

  def test_tsv_explicit_types
    codec = MrShell::Codecs::TSV.new(types: "string,integer,float,boolean,json")
    record = codec.load("001\t2\t3.5\tfalse\t{\"x\":1}\n")

    assert_equal "001", record.key
    assert_equal [2, 3.5, false, { "x" => 1 }], record.values
  end

  def test_tsv_round_trips_ambiguous_and_structured_values
    codec = MrShell::Codecs::TSV.new
    original = MrShell::Record.new("123", ["", "true", "a\tb", [1, 2], { "x" => 1 }])

    assert_equal original, codec.load("#{codec.dump(original)}\n")
  end

  def test_tsv_rejects_bad_explicit_conversion
    codec = MrShell::Codecs::TSV.new(types: "integer")

    error = assert_raises(MrShell::DataError) { codec.load("abc\n") }
    assert_match(/Cannot convert/, error.message)
  end

  def test_json_lines_accepts_array_and_object_records
    codec = MrShell::Codecs::JSONLines.new

    assert_equal MrShell::Record.new("a", [1]), codec.load("[\"a\",1]\n")
    assert_equal(
      MrShell::Record.new("a", [1]),
      codec.load("{\"key\":\"a\",\"values\":[1]}\n")
    )
  end

  def test_json_lines_round_trip
    codec = MrShell::Codecs::JSONLines.new
    record = MrShell::Record.new(["a", 1], [{ "nested" => true }])

    assert_equal record, codec.load(codec.dump(record))
  end

  def test_codec_factory_rejects_unknown_format
    assert_raises(MrShell::ConfigurationError) do
      MrShell::Codecs.build("yaml")
    end
  end
end

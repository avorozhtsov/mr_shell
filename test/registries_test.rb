# frozen_string_literal: true

require_relative "test_helper"

class RegistriesTest < Minitest::Test
  def test_codec_registry_accepts_a_custom_factory_and_alias
    registry = MrShell::CodecRegistry.new
    registry.register("pipe", "psv") do |**_options|
      MrShell::Codecs::TSV.new(input_separator: "|", output_separator: "|")
    end

    codec = registry.build("psv")

    assert_equal MrShell::Record.new("a", [1]), codec.load("a|1\n")
    assert_equal %w[pipe psv], registry.names
  end

  def test_stage_registry_builds_custom_stages
    registry = MrShell::StageRegistry.new
    registry.register("double") do
      MrShell::Stages::Map.new(
        ->(record) { MrShell::Record.new(record.key, [record.value * 2]) },
        name: "Double"
      )
    end
    pipeline = MrShell::Pipeline.new([MrShell::Record.new("a", [3])])
      .add_stage(registry.build("double"))

    assert_equal [MrShell::Record.new("a", [6])], pipeline.to_a
    assert_match(/Double/, pipeline.explain)
  end

  def test_registry_rejects_duplicates_and_unknown_names
    registry = MrShell::StageRegistry.new.register("one") { Object.new }

    assert_raises(MrShell::ConfigurationError) do
      registry.register("one") { Object.new }
    end
    assert_raises(MrShell::ConfigurationError) { registry.build("missing") }
  end
end

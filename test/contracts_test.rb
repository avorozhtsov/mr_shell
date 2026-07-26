# frozen_string_literal: true

require_relative "test_helper"

class ContractsTest < Minitest::Test
  def test_builtin_extensions_satisfy_their_contracts
    codec = MrShell::CodecRegistry.default.build("tsv")
    reducer = MrShell::ReducerRegistry.default.fetch("sum")
    stage = MrShell::StageRegistry.default.build(
      "map",
      function: ->(record) { record },
      name: "Identity"
    )
    records = [MrShell::Record.new("a", [1])]

    assert MrShell::Contracts.verify_codec(codec, records: records)
    assert MrShell::Contracts.verify_reducer(reducer, values: [1, 2, 3])
    assert MrShell::Contracts.verify_stage(stage, input: records)
  end

  def test_codec_contract_reports_a_bad_round_trip
    codec = Class.new do
      def name
        "Broken"
      end

      def dump(_record)
        "lost"
      end

      def load(_line)
        MrShell::Record.new("different", [])
      end
    end.new

    error = assert_raises(MrShell::ContractError) do
      MrShell::Contracts.verify_codec(
        codec,
        records: [MrShell::Record.new("original", [])]
      )
    end
    assert_match(/does not round-trip/, error.message)
  end

  def test_reducer_contract_rejects_shared_mutable_initial_state
    shared = []
    reducer = MrShell::ReducerDefinition.new(
      "broken",
      needs_value: true,
      initial: -> { shared },
      step: ->(accumulator, value) { accumulator << value },
      finalize: ->(accumulator) { accumulator }
    )

    error = assert_raises(MrShell::ContractError) do
      MrShell::Contracts.verify_reducer(reducer, values: [1])
    end
    assert_match(/reuses a mutable/, error.message)
  end

  def test_stage_contract_requires_the_protocol
    error = assert_raises(MrShell::ContractError) do
      MrShell::Contracts.verify_stage(Object.new, input: [])
    end
    assert_match(/call, explain|explain, call/, error.message)
  end
end

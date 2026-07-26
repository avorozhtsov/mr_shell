# mr_shell

A toy project for modeling the MapReduce paradigm, experimenting with
functional programming, and learning how a small framework is built.

This is an executable textbook, not a distributed MapReduce system.

## Project goals

The project optimizes for three things, in this order:

1. **Expressive power.** A short pipeline can express complete transformations,
   including arbitrary Ruby when built-in stages are not enough.
2. **Clear code.** The implementation keeps iteration, grouping, composition,
   and extension mechanisms visible.
3. **Framework-building practice.** The repository demonstrates protocols,
   registries, lazy plans, evaluation strategies, contract tests, layered
   testing, and correctness-first comparisons.

A feature belongs here when it makes one of those ideas easier to understand or
experiment with.

## Two-minute tour

The following command performs a complete word count:

```sh
printf 'red blue\t2\nblue\t1\n' |
  ruby bin/mr \
    --flat-map 'key.split.map { |word| [word, value] }' \
    --sort \
    --reduce sum \
    --explain
```

Data is written to standard output:

```text
blue    3
red     2
```

The executable plan is written separately to standard error:

```text
Input(TSV)
→ FlatMap(Ruby: key.split.map { |word| [word, value] })
→ External(sort)
→ ReduceByKey(sum)
→ Output(TSV)
```

The order of CLI transformation options is the order of execution. There is no
hidden optimizer rearranging the program.

## The big idea

A record consists of a key and zero or more values:

```ruby
MrShell::Record.new("blue", [2])
```

Reduction is a single pass over adjacent groups:

```text
a    1
a    2     -> a    3
b    3     -> b    3
```

The essential algorithm is:

```ruby
input.each do |record|
  emit(previous_group) if key_changed?(record)
  accumulators = reducers.map(&:initial) if new_group?
  accumulators = reducers.zip(accumulators).map do |reducer, accumulator|
    reducer.step(accumulator, record)
  end
end
emit(last_group)
```

Equal keys must be adjacent. Input `a, b, a` contains three groups, not two.
Use external `--sort`, in-memory `sort_by_key`, or provide already-grouped
input.

## Suggested reading order

The framework can be read in small layers:

1. [`Record`](lib/mr_shell/record.rb) — the data model.
2. [`Pipeline`](lib/mr_shell/pipeline.rb) — immutable plans and the stage
   protocol.
3. [`Stages`](lib/mr_shell/stages.rb) — lazy map/filter stages and the complete
   reduction loop.
4. [`ReducerRegistry`](lib/mr_shell/reducer_registry.rb) — `initial`, `step`,
   and `finalize`.
5. [`RubyEvaluator`](lib/mr_shell/ruby_evaluator.rb) — compiling user Ruby into
   stages.
6. [`CLI`](lib/mr_shell/cli.rb) — translating ordered options into a plan.
7. [`Comparison`](lib/mr_shell/comparison.rb) — correctness before metrics.

Codecs, subprocess handling, registries, and errors are adapters around that
core.

## How the framework is assembled

```text
input
  │
  ▼
Codec.load
  │
  ▼
Pipeline(source, [Stage, Stage, ...])
  │                     │
  │                     ├── built directly from Ruby blocks
  │                     └── built from source by RubyEvaluator
  ▼
Reducer(initial, step, finalize)
  │
  ▼
Codec.dump
  │
  ▼
output
```

`Pipeline` is immutable. Adding an operation returns a new pipeline containing
one more named stage. Nothing is processed until `each` is called.

```ruby
pipeline = MrShell::Pipeline.new(records)
mapped = pipeline.map(label: "Double") do |record|
  MrShell::Record.new(record.key, [record.value * 2])
end

puts mapped.explain
# Input(Enumerable)
# → Double
```

Lazy errors retain stage context:

```text
Map(Ruby: value.upcase) failed: undefined method `upcase' for 2
```

### The stage protocol

A custom stage needs only two methods:

```ruby
stage.explain     # human-readable plan entry
stage.call(input) # returns an enumerable
```

It can then be attached with:

```ruby
pipeline.add_stage(stage)
```

Subclassing `Stages::Base` is convenient but not required.

### Extension registries

`Framework` groups three registries:

```ruby
framework = MrShell::Framework.default
framework.reducers
framework.codecs
framework.stages
```

Registries map a name to a factory. New behavior is installed without changing
a central switch:

```ruby
framework.stages.register("double") do
  MrShell::Stages::Map.new(
    ->(record) { MrShell::Record.new(record.key, [record.value * 2]) },
    name: "Double"
  )
end

stage = framework.stages.build("double")
pipeline = pipeline.add_stage(stage)
```

Reducers are equally small:

```ruby
framework.reducers.register(
  "concat",
  initial: -> { [] },
  step: ->(accumulator, value) { accumulator + [value] },
  finalize: ->(accumulator) { accumulator.join(",") }
)
```

### Executable contracts

Framework extensions can be checked independently:

```ruby
MrShell::Contracts.verify_codec(codec, records: sample_records)
MrShell::Contracts.verify_reducer(reducer, values: sample_values)
MrShell::Contracts.verify_stage(stage, input: sample_records)
```

The checks verify protocol methods, codec round trips, fresh mutable reducer
state, and enumerable stage output. They complement normal behavior tests; they
do not replace them.

See [`custom_extensions.rb`](examples/custom_extensions.rb) for one executable
codec, reducer, stage, and contract example.

## Expressive Ruby stages

The CLI supports four evaluated transformations:

| Option | Expected result |
| --- | --- |
| `--map RUBY` | One `Record` or `[key, *values]` |
| `--filter RUBY` | A truthy or falsey value |
| `--flat-map RUBY` | An enumerable of records or record arrays |
| `--eval RUBY` | A complete `MrShell::Pipeline` |

Record expressions can use:

- `record` — the complete record;
- `key` — its key;
- `values` — its value array;
- `value` — the single value, or the array for a multivalue record.

For example:

```sh
ruby bin/mr \
  --filter 'value > 0' \
  --map '[key.upcase, Math.sqrt(value)]'
```

Full evaluation exposes `pipeline`, `registry`, and `framework`:

```sh
ruby bin/mr \
  --eval 'pipeline.reduce_by_key(registry.parse("sum"))'
```

This also lets an application-supplied framework expose custom stages:

```sh
ruby bin/mr \
  --eval 'pipeline.add_stage(framework.stages.build("my_stage"))'
```

These expressions are deliberately **not sandboxed**. They have the same file,
network, process, and environment access as `mr`. Only evaluate trusted source.

## The eval laboratory

Evaluation is a subject of the project rather than an implementation detail.
Five strategies implement the same `name`/`call` protocol:

| Strategy | Idea |
| --- | --- |
| `Direct` | An ordinary Ruby block |
| `Compiled` | Build one lambda with `eval`, then reuse it |
| `Repeated` | Call `eval` for every record |
| `Context` | Evaluate against a small object with `instance_eval` |
| `Parsed` | Check syntax with `Ripper`, then compile |

The CLI uses compile-once evaluation:

```ruby
evaluator = MrShell::RubyEvaluator.new
function = evaluator.compile("[key.upcase, value * 2]")
function.call(MrShell::Record.new("a", [3]))
# => ["A", 6]
```

Compilation and record-time errors become `EvaluationError`; when they occur
inside a lazy stage, `StageError` adds the plan entry that failed.

Ripper validation checks syntax, not safety. None of these approaches is a
sandbox.

## Comparing approaches

Run the comparisons with:

```sh
SIZE=100000 ruby examples/compare_approaches.rb
SIZE=100000 ruby examples/compare_eval.rb
```

The MapReduce comparison includes:

- eager `group_by`;
- standard `Enumerator::Lazy`;
- in-process `MrShell::Pipeline`;
- Unix `sort` feeding a streaming reducer.

The eval comparison includes all five strategies above.

Both programs use `MrShell::Comparison`, which refuses to benchmark approaches
until their materialized results are equal. It then reports:

- total time;
- time until the first result;
- allocated Ruby objects;
- approximate peak Ruby heap above the baseline.

Heap sampling changes the workload slightly and does not include all native or
subprocess memory. Use the figures to understand direction and tradeoffs, not
as publication-quality benchmarks.

## Progressive examples

Read or execute these in order:

| Example | New idea |
| --- | --- |
| [`01_grouped_sum.rb`](examples/01_grouped_sum.rb) | The reduction invariant |
| [`word_count.rb`](examples/word_count.rb) | `flat_map → sort → reduce` |
| [`eval_pipeline.rb`](examples/eval_pipeline.rb) | Source text creating a stage |
| [`custom_extensions.rb`](examples/custom_extensions.rb) | Registries and contracts |
| [`compare_approaches.rb`](examples/compare_approaches.rb) | Alternative data-processing approaches |
| [`compare_eval.rb`](examples/compare_eval.rb) | Alternative evaluation approaches |

The examples are executed by the test suite, so documentation cannot silently
drift away from the framework.

## Built-in reducers

Multiple reducers can be separated by semicolons:

```sh
ruby bin/mr --reduce 'sum[0];avg[1];count'
```

Selectors are zero-based value-field indices.

| Reducer | Result |
| --- | --- |
| `sum` | Sum of numeric values |
| `prod` | Product |
| `min`, `max` | Minimum or maximum |
| `count` | Record count; does not accept a selector |
| `avg` | Arithmetic mean |
| `stddev` (`sigma`) | Population standard deviation |
| `relative_stddev` (`rsigma`) | Deviation divided by absolute mean |
| `collect` (`join`) | Values in input order |
| `uniq` | Unique values in first-seen order |
| `frequency` (`freq`) | Value-to-count map |

Numeric reducers use constant memory. `collect`, `uniq`, and `frequency`
retain group data.

## Input, output, and sorting

TSV is the default. It recognizes strict integers, floats, scientific notation,
JSON containers, booleans, and `null`. Explicit column types can be supplied:

```sh
ruby bin/mr --convert string,integer,float
```

Supported types are `auto`, `string`, `integer`, `float`, `boolean`, and
`json`.

JSONL input accepts either form:

```json
["key", 10, 20]
{"key":"key","values":[10,20]}
```

Use `--input-format jsonl` and `--output-format jsonl`. Output uses the compact
array form.

Other useful options:

```text
--key 0,2       choose complete-record columns as the key
--no-key        treat all input as one group
--sort          use external `sort`
--check-sorted  reject decreasing keys before reduction
--list-reducers list reducer names
--explain       print the plan to stderr
```

External sorting operates on the serialized representation. It groups equal
keys, but lexical order can differ from semantic numeric order.

## Testing the framework

```sh
bundle exec rake test
bundle exec rubocop
```

The suite is intentionally layered:

- unit tests specify records, codecs, reducer math, and eval strategies;
- contract tests specify extension protocols;
- pipeline tests specify laziness, plan explanation, grouping, and stage errors;
- property-style randomized tests compare reduction with eager `group_by`;
- round-trip tests check `load(dump(record)) == record`;
- approach tests keep alternative implementations equivalent;
- golden CLI tests check complete stdin/stdout behavior;
- example tests execute the learning path;
- subprocess tests cover external success and failure.

Useful laws include:

```text
map(identity) == input
filter(always_true) == input
reduce(sorted input) == eager group_by reduction
codec.load(codec.dump(record)) == record
all comparison approaches return the same result
```

Benchmarks report observations; they do not impose unstable performance
thresholds in CI.

## Complexity

For `n` records and `r` reducers:

- `map`, `filter`, and `flat_map` are streaming;
- `reduce_by_key` takes `O(nr)` time and `O(r)` accumulator memory for
  constant-space reducers;
- `sort_by_key` takes `O(n)` memory;
- external `sort` manages sorting storage outside the Ruby process;
- `uniq_by` uses memory proportional to distinct identities;
- collection reducers use memory proportional to their group.

## Anti-goals

The project intentionally does not try to provide:

- distributed execution;
- production-grade code sandboxing;
- a SQL replacement;
- transparent parallelism;
- every historical command-line option;
- a large inheritance hierarchy;
- optimization before semantic equivalence is demonstrated.

Those are worthwhile projects, but adding them here would obscure the lesson.

## Installation and development

The library targets Ruby 3.3 or later and has no runtime gem dependencies.

```sh
bundle install
bundle exec ruby bin/mr --help
bundle exec rake test
bundle exec rubocop
gem build mr_shell.gemspec
```

The repository currently has no declared software license.

defmodule ExStatsD.DecoratorTest do
  use ExUnit.Case, async: false

  @stubbed_timing 1.234

  defmodule DecoratedModule do
    use ExStatsD.Decorator

    deftimed simple do
      result = :simple
      result
    end

    @metric "custom_key"
    deftimed custom_name, do: :custom_name

    deftimed custom_name_gone, do: :custom_name_gone

    @metric "multi_0_or_1"
    deftimed multi(0), do: 0
    deftimed multi(1), do: 1
    @metric "multi_other"
    deftimed multi(x), do: x

    @metric_options [tags: [:mytag]]
    deftimed with_options, do: :with_options
    deftimed options_gone, do: :options_gone

    @metric_options [tags: [:options_fall_through]]
    deftimed multi_options(0), do: 0
    deftimed multi_options(1), do: 1
    @metric_options [tags: [:options_get_changed]]
    deftimed multi_options(x), do: x

    @use_histogram true
    deftimed multi_attrs(x, y), do: {x, y}
    deftimed multi_attrs(x, y, z), do: {x, y, z}

    @default_metric_options [tags: ["mine"]]
    deftimed ignored_attr(_x), do: :ignored_attr
    deftimed unbound_attr(_), do: :unbound_attr

    deftimed guarded(x) when is_list(x), do: {:ok, x}
    deftimed guarded(_x), do: {:error, :not_a_list}

  end

  setup do
    {:ok, pid} = ExStatsD.start_link
    # Lets cheat for sampling here. Setting the seed like this should set the
    # 3 next calls to :random.uniform as 0.01, 0.89 and 0.11
    :random.seed(0, 0, 0)
    {:ok, pid: pid}
  end

  @prefix "test.function_call.elixir.exstatsd.decoratortest.decoratedmodule."

  test "basic wrapper with defaults" do
    assert DecoratedModule.simple === :simple
    expected = [@prefix<>"simple_0:1.234|ms", call_count(@prefix<>"simple_0")]
    assert sent == expected
  end

  test "custom metric name" do
    assert DecoratedModule.custom_name === :custom_name
    expected = ["test.custom_key:1.234|ms", call_count("test.custom_key")]
    assert sent == expected
  end

  test "custom metric name does not leak to next function" do
    assert DecoratedModule.custom_name === :custom_name
    assert DecoratedModule.custom_name_gone === :custom_name_gone
    expected = [
      @prefix<>"custom_name_gone_0:1.234|ms",
      call_count(@prefix<>"custom_name_gone_0"),
      "test.custom_key:1.234|ms",
      call_count("test.custom_key")
    ]
    assert sent == expected
  end

  defp call_count(bucket) do
    # (String.split(bucket, ":") |> Enum.at(0)) <> ".call_count:1|c"
    bucket <> ".call_count:1|c"
  end

  test "custom metric name falling to next in match unless changed" do
    assert DecoratedModule.multi(0) === 0
    assert DecoratedModule.multi(1) === 1
    assert DecoratedModule.multi(2) === 2
    expected = [
      "test.multi_other:1.234|ms", call_count("test.multi_other"),
      "test.multi_0_or_1:1.234|ms", call_count("test.multi_0_or_1"),
      "test.multi_0_or_1:1.234|ms", call_count("test.multi_0_or_1"),
    ]
    assert sent == expected
  end

  test "tags are set and don't leak" do
    assert DecoratedModule.with_options === :with_options
    assert DecoratedModule.options_gone === :options_gone
    expected = [
      @prefix<>"options_gone_0:1.234|ms", call_count(@prefix<>"options_gone_0"),
      @prefix<>"with_options_0:1.234|ms|#mytag", call_count(@prefix<>"with_options_0")
    ]
    assert sent == expected
  end

  test "tags fall through and get updated" do
    assert DecoratedModule.multi_options(0) === 0
    assert DecoratedModule.multi_options(1) === 1
    assert DecoratedModule.multi_options(2) === 2
    expected = [
      @prefix<>"multi_options_1:1.234|ms|#options_get_changed",
      call_count(@prefix<>"multi_options_1"),
      @prefix<>"multi_options_1:1.234|ms|#options_fall_through",
      call_count(@prefix<>"multi_options_1"),
      @prefix<>"multi_options_1:1.234|ms|#options_fall_through",
      call_count(@prefix<>"multi_options_1"),
    ]
    assert sent == expected
  end

  test "send using histogram when enabled in all following functions" do
    assert DecoratedModule.multi_attrs(1, 2) === {1, 2}
    assert DecoratedModule.multi_attrs(1, 2, 3) === {1, 2, 3}
    expected = [
      @prefix<>"multi_attrs_3:1.234|h", call_count(@prefix<>"multi_attrs_3"),
      @prefix<>"multi_attrs_2:1.234|h", call_count(@prefix<>"multi_attrs_2"),
    ]
    assert sent == expected
  end

  test "default options can be changed" do
    assert DecoratedModule.ignored_attr(:ingnored) === :ignored_attr
    assert DecoratedModule.unbound_attr(:unbound) === :unbound_attr
    expected = [
      @prefix<>"unbound_attr_1:1.234|h|#mine",
      call_count(@prefix<>"unbound_attr_1"),
      @prefix<>"ignored_attr_1:1.234|h|#mine",
      call_count(@prefix<>"ignored_attr_1"),
    ]
    assert sent == expected
  end

  defp sent, do: :sys.get_state(ExStatsD).sink

end

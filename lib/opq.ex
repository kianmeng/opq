defmodule OPQ do
  @moduledoc """
  A simple, in-memory queue with worker pooling and rate limiting in Elixir.
  """

  alias OPQ.{Options, Feeder, RateLimiter, WorkerSupervisor}
  alias OPQ.OptionsHandler, as: Opt

  def child_spec(opts \\ []) do
    %{
      id: opts[:name],
      start: {OPQ, :start_link, [opts]}
    }
  end

  def start_link(opts \\ []), do: init(opts)

  def init(opts \\ []) do
    opts
    |> Options.assign_defaults()
    |> start_links()
  end

  def enqueue(feeder, event) do
    GenStage.cast(feeder, {:enqueue, event})
  end

  def enqueue(feeder, mod, fun, args)
      when is_atom(mod) and
             is_atom(fun) and
             is_list(args) do
    enqueue(feeder, {mod, fun, args})
  end

  def stop(feeder) do
    Process.flag(:trap_exit, true)
    GenStage.cast(feeder, :stop)
    Opt.stop(feeder)
  end

  def pause(feeder), do: GenStage.cast(feeder, :pause)
  def resume(feeder), do: GenStage.cast(feeder, :resume)
  def info(feeder), do: GenStage.call(feeder, :info, Opt.timeout(feeder))
  def queue(feeder), do: GenStage.call(feeder, :queue, Opt.timeout(feeder))

  defp start_links(opts) do
    {:ok, feeder} = Feeder.start_link(opts[:name])

    Opt.save_opts(opts[:name] || feeder, opts)

    opts
    |> Keyword.merge(name: feeder)
    |> start_consumers(interval: opts[:interval])

    {:ok, feeder}
  end

  defp start_consumers(opts, interval: 0) do
    opts
    |> Keyword.merge(producer_consumer: opts[:name])
    |> WorkerSupervisor.start_link()
  end

  defp start_consumers(opts, _) do
    {:ok, rate_limiter} = RateLimiter.start_link(opts)

    opts
    |> Keyword.merge(producer_consumer: rate_limiter)
    |> WorkerSupervisor.start_link()
  end
end

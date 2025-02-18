defmodule OPQTest do
  use OPQ.TestCase, async: true

  doctest OPQ

  test "enqueue items - child_spec/1" do
    Supervisor.start_link([{OPQ, name: :opq}], strategy: :one_for_one)

    OPQ.enqueue(:opq, :a)
    OPQ.enqueue(:opq, :b)

    wait(fn ->
      assert_empty_queue(:opq)
    end)
  end

  test "enqueue items - start_link/1" do
    {:ok, opq} = OPQ.start_link()

    OPQ.enqueue(opq, :a)
    OPQ.enqueue(opq, :b)

    wait(fn ->
      assert_empty_queue(opq)
    end)
  end

  test "enqueue items - init/1" do
    {:ok, opq} = OPQ.init()

    OPQ.enqueue(opq, :a)
    OPQ.enqueue(opq, :b)

    wait(fn ->
      assert_empty_queue(opq)
    end)
  end

  test "enqueue functions" do
    Agent.start_link(fn -> [] end, name: Bucket)

    {:ok, opq} = OPQ.init()

    OPQ.enqueue(opq, fn -> Agent.update(Bucket, &[:a | &1]) end)
    OPQ.enqueue(opq, fn -> Agent.update(Bucket, &[:b | &1]) end)

    wait(fn ->
      assert_empty_queue(opq)

      assert Kernel.length(Agent.get(Bucket, & &1)) == 2
    end)
  end

  test "enqueue MFAs" do
    Agent.start_link(fn -> [] end, name: MfaBucket)

    {:ok, opq} = OPQ.init()

    OPQ.enqueue(opq, Agent, :update, [MfaBucket, &[:a | &1]])
    OPQ.enqueue(opq, Agent, :update, [MfaBucket, &[:b | &1]])

    wait(fn ->
      assert_empty_queue(opq)

      assert Kernel.length(Agent.get(MfaBucket, & &1)) == 2
    end)
  end

  test "enqueue to a named queue" do
    OPQ.init(name: :items)

    OPQ.enqueue(:items, :a)
    OPQ.enqueue(:items, :b)

    wait(fn ->
      assert_empty_queue(:items)
    end)
  end

  test "run out of demands from the workers" do
    {:ok, opq} = OPQ.init(workers: 2)

    OPQ.enqueue(opq, :a)
    OPQ.enqueue(opq, :b)

    wait(fn ->
      assert_empty_queue(opq)
    end)
  end

  test "single worker" do
    {:ok, opq} = OPQ.init(workers: 1)

    OPQ.enqueue(opq, :a)
    OPQ.enqueue(opq, :b)

    wait(fn ->
      assert_empty_queue(opq)
    end)
  end

  test "custom worker" do
    defmodule CustomWorker do
      def start_link(item) do
        Task.start_link(fn ->
          Agent.update(CustomWorkerBucket, &[item | &1])
        end)
      end
    end

    Agent.start_link(fn -> [] end, name: CustomWorkerBucket)

    {:ok, opq} = OPQ.init(worker: CustomWorker)

    OPQ.enqueue(opq, :a)
    OPQ.enqueue(opq, :b)

    wait(fn ->
      assert Kernel.length(Agent.get(CustomWorkerBucket, & &1)) == 2
    end)
  end

  test "rate limit" do
    Agent.start_link(fn -> [] end, name: RateLimitBucket)

    {:ok, opq} = OPQ.init(workers: 1, interval: 10)

    Task.async(fn ->
      OPQ.enqueue(opq, fn -> Agent.update(RateLimitBucket, &[:a | &1]) end)
      OPQ.enqueue(opq, fn -> Agent.update(RateLimitBucket, &[:b | &1]) end)
    end)

    Process.sleep(5)

    assert Kernel.length(Agent.get(RateLimitBucket, & &1)) == 1

    wait(fn ->
      assert Kernel.length(Agent.get(RateLimitBucket, & &1)) == 2
    end)
  end

  test "stop" do
    {:ok, opq} = OPQ.init(workers: 1)

    OPQ.enqueue(opq, :a)

    OPQ.stop(opq)

    refute Process.alive?(opq)

    agent = :"opq-#{Kernel.inspect(opq)}"

    assert catch_exit(Agent.get(agent, & &1))
  end

  test "pause & resume" do
    Agent.start_link(fn -> [] end, name: PauseBucket)

    {:ok, opq} = OPQ.init(workers: 1)

    OPQ.enqueue(opq, fn -> Agent.update(PauseBucket, &[:a | &1]) end)

    OPQ.pause(opq)

    OPQ.enqueue(opq, fn -> Agent.update(PauseBucket, &[:b | &1]) end)
    OPQ.enqueue(opq, fn -> Agent.update(PauseBucket, &[:c | &1]) end)

    wait(fn ->
      {status, _queue, _demand} = OPQ.info(opq)

      assert status == :paused
      assert Kernel.length(Agent.get(PauseBucket, & &1)) == 1
    end)

    OPQ.resume(opq)

    wait(fn ->
      {status, _queue, _demand} = OPQ.info(opq)

      assert status == :normal
      assert Kernel.length(Agent.get(PauseBucket, & &1)) == 3
    end)
  end

  defp assert_empty_queue(queue_name) do
    assert queue_name
           |> OPQ.queue()
           |> Enum.empty?()
  end
end

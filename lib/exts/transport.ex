require Logger
defmodule Exts.Transport do
  use GenServer

  alias Exts.TsState

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, [])
  end

  def init(opts) do
    summary_interval = opts[:summary_interval]
    callback = cond do
      opts[:callback] != nil -> opts[:callback]
      True -> {Exts.Callbacks.Dummy, nil}
    end
    state = %{
      std_summary_interval: summary_interval,
      ts_state: %TsState{
        :callback => callback
      }
    }
    if summary_interval != nil do
      Process.send_after(self(), :summary, summary_interval)
    end
    {:ok, state}
  end

  def info(pid) do
    GenServer.call(pid, :info)
  end

  def feed(pid, buffer) do
    GenServer.call(pid, {:feed, buffer})
  end

  def handle_call({:feed, buffer}, _from, state) do
    new_ts_state = Exts.Parser.Ts.parse(buffer, state.ts_state)
    {:reply, :ok, %{state | :ts_state => new_ts_state}}
  end

  def handle_call(:info, _from, state) do
    IO.inspect state.ts_state
    {:reply, state.ts_state, state}
  end

  def handle_info(:summary, state) do
    IO.puts IO.ANSI.clear
    IO.puts state.ts_state
    Process.send_after(self(), :summary, state.std_summary_interval)
    {:noreply, state}
  end
end

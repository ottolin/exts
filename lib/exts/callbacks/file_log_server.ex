defmodule Exts.Callbacks.FileLogServer do
  @behaviour Exts.TsCallback
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, [])
  end

  # TsCallback behavior
  def pcr_tick(ctx, program_pid, pcr_pid, pcr_pos, pcr) do
    GenServer.cast(ctx, {:pcr_tick, program_pid, pcr_pid, pcr_pos, pcr})
  end

  def program_detected(ctx, program) do
    GenServer.cast(ctx, {:program_detected, program})
  end

  def program_updated(ctx, program) do
    GenServer.cast(ctx, {:program_updated, program})
  end

  def stream_detected(ctx, stream) do
    GenServer.cast(ctx, {:stream_detected, stream})
  end

  def stream_updated(ctx, stream) do
    GenServer.cast(ctx, {:stream_updated, stream})
  end

  def stream_timestamps_detected(ctx, pid, pos, pcr_pos, pcr, pts, dts) do
    GenServer.cast(ctx, {:stream_timestamps_detected, pid, pos, pcr_pos, pcr, pts, dts})
  end

  def flush(ctx) do
    GenServer.call(ctx, :flush)
  end

  # GenServer callbacks
  def init(opts) do
    state = %{
      stream_logs: %{},
      pcr_logs: %{},
      prev_pcr: %{},
      output_folder: opts[:output_folder],
    }
    File.mkdir_p(state.output_folder)
    {:ok, state}
  end

  def handle_cast({:pcr_tick, _program_pid, pcr_pid, pcr_pos, pcr}, state) do
    f = Map.get(state.pcr_logs, pcr_pid, :error_no_program_detected)
    {prev_pcr_pos, prev_pcr} = Map.get(state.prev_pcr, pcr_pid, {-1, -1})

    bitrate = if prev_pcr_pos != -1 do
      1504*(pcr_pos - prev_pcr_pos) * 27000000 / (pcr - prev_pcr)
    else
      -1
    end
    str = "#{pcr_pos}, #{pcr}, #{bitrate}"
    IO.puts(f, str)

    new_prev_pcr = Map.put(state.prev_pcr, pcr_pid, {pcr_pos, pcr})
    {:noreply, %{state | :prev_pcr => new_prev_pcr}}
  end

  def handle_cast({:program_detected, _program}, state) do
    #IO.puts "Program detected!!"
    #IO.inspect program
    {:noreply, state}
  end

  def handle_cast({:program_updated, program}, state) do
    pcr_path = Path.join(state.output_folder, "pcr-#{program.pcr_pid}.csv")
    {:ok, f} = Map.get(state.pcr_logs, program.pcr_pid, File.open(pcr_path, [:write, :delayed_write]))
    IO.puts(f, "pkt_pos, pcr, bitrate")
    new_pcr_logs = Map.put(state.pcr_logs, program.pcr_pid, f)
    {:noreply, %{state | :pcr_logs => new_pcr_logs}}
  end

  def handle_cast({:stream_detected, stream}, state) do
    stream_path = Path.join(state.output_folder, "#{stream.pid}.csv")
    {:ok, f} = Map.get(state.stream_logs, stream.pid, File.open(stream_path, [:write, :delayed_write]))
    IO.puts(f, "pkt_pos, pcr_pos, pcr, pts, dts, dts-pcr")
    new_stream_logs = Map.put(state.stream_logs, stream.pid, f)
    {:noreply, %{state | :stream_logs => new_stream_logs}}
  end

  def handle_cast({:stream_updated, _stream}, state) do
    #IO.puts "Stream updated!!"
    #IO.inspect stream
    {:noreply, state}
  end

  def handle_cast({:stream_timestamps_detected, pid, pos, pcr_pos, pcr, pts, dts}, state) do
    f = Map.get(state.stream_logs, pid, :error_stream_detected)
    IO.puts(f, "#{pos}, #{pcr_pos}, #{pcr}, #{pts}, #{dts}, #{dts - pcr}")
    {:noreply, state}
  end

  def handle_call(:flush, _from, state) do
    Map.values(state.pcr_logs)
    |> Enum.each(&(File.close(&1)))
    {:reply, :ok, state}
  end
end

defmodule Exts.Callbacks.Dummy do
  @behaviour Exts.TsCallback

  def pcr_tick(_ctx, _program_pid, _pcr_pid, _pcr_pos, _pcr) do
  end

  def program_detected(_ctx, _program) do
  end

  def program_updated(_ctx, _program) do
  end

  def stream_detected(_ctx, _stream) do
  end

  def stream_updated(_ctx, _stream) do
  end

  def stream_timestamps_detected(_ctx, _pid, _pos, _pcr_pos, _pcr, _pts, _dts) do
  end
end

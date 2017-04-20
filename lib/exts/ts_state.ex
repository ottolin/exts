import Kernel, except: [to_string: 1]

defmodule Exts.TsState do
  defstruct pos: 0,
    residue: <<>>,
    programs: [], # List of TsProgram
    streams: [], # List of TsStream
    pid_residue: %{},
    statistics: %{},
    callback: {Exts.Callbacks.Dummy, nil}
end

defmodule Exts.TsProgram do
  defstruct pid: -1,
    pgm_num: -1,
    pcr_pid: -1,
    cur_pcr: {-1, -1} # {position, pcr}
end

defmodule Exts.TsStream do
  defstruct pid: -1,
    pmt_pid: -1,
    type: :unknown # :unknown, :aac, :m1l2, :ac3, :dolbye, :mpeg2v, :avc, :hevc, :subtitle, :teletext, :scte35, :id3, :avs, :vc1
end

defmodule Exts.TsStatistics do
  defstruct pid: -1,
    last_cc: -1,
    ccerrors: 0,
    npkts: 0
end

defmodule Exts.TsCallback do
  @doc """
  Callback for PCR
  Arguments: context, program_pid, pcr_pid, pcr_pos, pcr
  """
  @callback pcr_tick(any, integer, integer, integer, integer) :: none
  @callback program_detected(any, %Exts.TsProgram{}) :: none
  @callback program_updated(any, %Exts.TsProgram{}) :: none
  @callback stream_detected(any, %Exts.TsStream{}) :: none
  @callback stream_updated(any, %Exts.TsStream{}) :: none

  @doc """
  Callback for PTS/DTS
  Arguments: context, pid, pos, pcr_pos, pcr, pts, dts
  """
  @callback stream_timestamps_detected(any, integer, integer, integer, integer, integer, integer) :: none
end

defimpl String.Chars, for: Exts.TsState do
  def to_string(state) do
    state |> Exts.Printer.ts_state_to_string
  end
end

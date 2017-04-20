defmodule Exts.Parser.Ts do
  alias Exts.TsState
  alias Exts.Parser

  def parse(data, %TsState{residue: <<>>} = state) when is_binary(data) do
    # No residue left last time. directly calling ts parsing
    parse_ts(data, state)
  end

  def parse(data, %TsState{residue: last_residue} = state) when is_binary(data) do
    parse_ts(last_residue <> data, state)
  end

  # function to handle non-188 align buffer.
  # although we wont use it that way in the inspects module
  defp parse_ts(<<0x47, ts_data::binary-size(187), rest::binary>>, state) do
    # sync byte matched, doing real ts parsing
    updated_state = parse_ts_187(ts_data, %{state | pos: state.pos + 1})
    parse_ts(rest, updated_state)
  end

  defp parse_ts(<<_::8, rest::binary>> = data, state) when byte_size(rest) >= 188 do
    parse_ts(rest, state)
  end

  defp parse_ts(tspkt_smaller_than_188, state) do
    # simply drop it?
    %{state | residue: tspkt_smaller_than_188}
  end

  # function to extract ts payload
  defp payload(<<_::18, 0::1, 1::1, _cc::4, payload::binary>>) do
    payload
  end

  defp payload(<<_::18, 1::1, 1::1, _cc::4, adap_len::8, _adap::binary-size(adap_len), payload::binary>>) do
    payload
  end

  defp payload(<<_::18, _::1, 0::1, _cc::4, _payload::binary>>) do
    <<>>
  end

  defp get_type(pid, state) do
    cond do
      pid == 0 -> :pat
      pid in Enum.map(state.programs, fn pgm -> pgm.pid end) -> :pmt
      True -> :data
    end
  end

  defp parse_adap_field(<<_discon::1, _rai::1, _priority::1, 1::1, _opcr::1, _splice::1, _tspriv::1, _ext::1, pcr33::33, _pad::6, pcr_ext::9, _rest::binary>> = _adap_field_bytes) do
    # we only care about pcr right now. can extend for other fields in the future
    pcr = (pcr33 * 300) + pcr_ext
    {pcr}
  end

  defp parse_adap_field(_) do
    {-1}
  end

  defp ts_statistics(pid, _scramble, payload, cc, state) do
    cur_cc = rem(cc, 16)
    statistics = Map.get(state.statistics, pid, %Exts.TsStatistics{pid: pid, last_cc: cur_cc - 1})
    exp_cc = if payload != 0 do
      rem(statistics.last_cc + 1, 16)
    else
      statistics.last_cc
    end

    # update cc error count
    statistics =
      cond do
        pid < 8191 && cur_cc != exp_cc ->
          %{statistics | ccerrors: statistics.ccerrors + 1}
        True -> statistics
      end
    statistics = %{statistics | last_cc: cur_cc, npkts: statistics.npkts+1}
    %{state | statistics: Map.put(state.statistics, pid, statistics)}
  end

  defp parse_ts_header(<<_::3, pid::13, _scramble::2, 1::1, _::1, _cc::4, adap_len::8, adap::binary-size(adap_len), _payload::binary>>, state) do
    # currently we only care PCR. can extend for other fields also.
    {pcr} = parse_adap_field(adap)
    if pcr != -1 do
      cur_pcr = {state.pos, pcr}
      programs = state.programs
      |> Enum.map(
      fn p ->
        cond do
          p.pcr_pid == pid ->
            {cb, cb_ctx} = state.callback
            cb.pcr_tick(cb_ctx, p.pid, p.pcr_pid, state.pos, pcr)
            %{p| cur_pcr: cur_pcr}
          True -> p
        end
      end)

      %{state | programs: programs}
    else
      state
    end
  end

  defp parse_ts_header(_, state) do
    state
  end

  defp parse_ts_187(<<_tei::1, pusi::1, _priority::1, pid::13, scramble::2, _::1, payload::1, cc::4, _::binary>> = data, state) when is_binary(data) do
    state = ts_statistics(pid, scramble, payload, cc, state)
    state = parse_ts_header(data, state)
    parse_data(get_type(pid, state), pid, pusi, data, state)
  end

  defp parse_data(:pat, 0, pusi, data, state) do
    data
    |> payload
    |> Parser.Psi.pat(pusi, state)
  end

  defp parse_data(:pmt, pid, pusi, data, state) do
    data
    |> payload
    |> Parser.Psi.pmt(pusi, pid, state)
  end

  defp parse_data(:data, _pid, 0, _data, state) do
    # no pusi, just ignore as we only care header now
    state
  end

  defp parse_data(:data, pid, 1, data, state) do
    parse_pes_header(pid, 1, payload(data), state)
  end

  defp parse_pes_header(pid, 1, <<0x00, 0x00, 0x01, _stream_id::8, _pes_len::16, pes_header_and_rest::binary>>, state) do
    stream = get_stream(pid, state)
    if stream != nil do
      {pts, dts} = Parser.Pes.pts_dts(pes_header_and_rest)
      {pcr_pos, pcr} = get_cur_pcr_for_stream(pid, state)

      # Callback
      {cb, cb_ctx} = state.callback
      cb.stream_timestamps_detected(cb_ctx, pid, state.pos, pcr_pos, pcr, pts, dts)
    end
    state
  end

  defp parse_pes_header(_pid, 1, no_pes_header, state) when is_binary(no_pes_header)do
    state
  end

  ## Helper functions for state
  defp get_cur_pcr_for_stream(pid, state) do
    pid
    |> get_stream(state)
    |> get_pgm_from_stream(state)
    |> get_pcr_from_pgm
  end

  defp get_pcr_from_pgm(nil) do
    {-1, -1}
  end

  defp get_pcr_from_pgm(program) do
    program.cur_pcr
  end

  defp get_pgm_from_stream(nil, _state) do
    nil
  end

  defp get_pgm_from_stream(stream, state) do
    get_pgm(stream.pmt_pid, state)
  end

  defp get_pgm(nil, _state) do
    nil
  end

  defp get_pgm(pmt_pid, state) do
    Enum.find(state.programs, fn p -> p.pid == pmt_pid end)
  end

  defp get_stream(pid, state) do
    Enum.find(state.streams, fn s -> s.pid == pid end)
  end
end

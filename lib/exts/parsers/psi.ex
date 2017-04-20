defmodule Exts.Parser.Section do
  defstruct table_id: -1,
  section_syntax_indicator: -1,
  private_indicator: -1,
  reserved1: 0,
  section_length: 0,
  table_id_ext: -1,
  reserved2: 0,
  version: -1,
  cur_next_ind: -1,
  section_num: -1,
  last_section_num: -1,
  payload: "",
  crc32: 0

  def parse(<<table_id::8, 1::1, private_indicator::1, reserved1::2,
            section_length::12, table_id_ext::16, reserved2::2, version::5, cur_next_ind::1,
            section_num::8, last_section_num::8, rest::binary>>) do

    # section_syntax_indicator == 1, long section
    payload_len = section_length - 9;
    <<payload::binary-size(payload_len), crc32::32, _::binary>> = rest

    %Exts.Parser.Section{
      table_id: table_id,
      section_syntax_indicator: 1,
      private_indicator: private_indicator,
      reserved1: reserved1,
      section_length: section_length,
      table_id_ext: table_id_ext,
      reserved2: reserved2,
      version: version,
      cur_next_ind: cur_next_ind,
      section_num: section_num,
      last_section_num: last_section_num,
      payload: payload,
      crc32: crc32
    }
  end

  def parse(<<table_id::8, 0::1, private_indicator::1, reserved1::2,
            section_length::12, payload::binary-size(section_length)>>) do

    # section_syntax_indicator == 0, short section
    %Exts.Parser.Section{
      table_id: table_id,
      section_syntax_indicator: 0,
      private_indicator: private_indicator,
      reserved1: reserved1,
      section_length: section_length,
      payload: payload,
    }
  end

  def parse(_) do
    :cannot_parse
  end
end

defmodule Exts.Parser.Psi do

  def pat(section_bytes) do
    section = Exts.Parser.Section.parse(section_bytes)
    case section do
      :cannot_parse ->
        :cannot_parse
      _ ->
        get_pgm(section.payload)
    end
  end

  def pat(data, pusi, state) do
    {buffer, new_state} = handle_section_buffer(data, pusi, 0, state)
    if buffer != <<>> do
      new_programs = buffer
      |> pat
      |> Enum.filter(fn {pid, _pgm_num} ->
        not pid in Enum.map(state.programs, fn pgm -> pgm.pid end)
      end)
      |> Enum.map(fn {pid, pgm_num} ->
        %Exts.TsProgram{pid: pid, pgm_num: pgm_num}
      end)

      # callback
      {cb, cb_ctx} = state.callback
      new_programs |> Enum.each(&(cb.program_detected(cb_ctx, &1)))

      updated_programs = state.programs ++ new_programs
      %{new_state | programs: updated_programs}
    else
      new_state
    end
  end

  def pmt(section_bytes) do
    section = Exts.Parser.Section.parse(section_bytes)

    <<_::3, pcr_pid::13, _::4, pgm_info_len::12, _pgm_desc::binary-size(pgm_info_len), stream_info_bytes::binary>> = section.payload
    {pcr_pid, get_stream(stream_info_bytes)}
  end

  def pmt(data, pusi, pmt_pid, state) do
    {buffer, new_state} = handle_section_buffer(data, pusi, pmt_pid, state)
    if buffer != <<>> do
      {pcr_pid, stream_list} = buffer |> pmt
      # Creating stream according to pmt result
      new_streams = stream_list
      |> Enum.filter(fn {pid, _stream_type} ->
        not pid in Enum.map(state.streams, fn stm -> stm.pid end)
      end)
      |> Enum.map(fn {pid, stream_type} -> %Exts.TsStream{pid: pid, pmt_pid: pmt_pid, type: stream_type} end)

      {cb, cb_ctx} = state.callback
      new_streams |> Enum.each(&(cb.stream_detected(cb_ctx,&1)))

      # Set pcr pid to program
      updated_programs = Enum.map(state.programs,
        fn p ->
          cond do
            (p.pcr_pid == -1 && p.pid == pmt_pid) ->
              updated_p = %{p | pcr_pid: pcr_pid}
              cb.program_updated(cb_ctx, updated_p)
              updated_p
            True -> p
          end
        end)
      updated_streams = state.streams ++ new_streams
      %{new_state | programs: updated_programs, streams: updated_streams}
    else
      new_state
    end
  end

  defp handle_section_buffer(data, pusi, pid, state) do
    last_residue = Map.get(state.pid_residue, pid, <<>>)
    {buffer, new_residue} = if (<<>> != last_residue) do
      if 0 == pusi do
        {<<>>, last_residue <> data}
      else
        # pusi = true, but already having some parsing buffer, it's NOT a new section,
        # we should just skip the pointer byte and keep the end of last table in our parsing buffer.
        # e.g. [0x47][pusi = 1][pointer byte = 0x80][End of last table section][Start of new table section]
        #                |             ^      |                                ^
        #                |_____________|      |________________________________|
        #
        <<ptr_field::8, rest::binary>> = data
        if ptr_field > 0 do
          <<prev_section::binary-size(ptr_field), section_bytes::binary>> = rest
          {last_residue <> prev_section, section_bytes}
        else
          {last_residue, rest}
        end
      end
    else
      if 0 == pusi do
        # we have no last_residue, but we do not have any pusi yet.
        # so we should do nothing and wait for new section
        {<<>>, <<>>}
      else
        # no last_residue, and now we have new section start
        # we can start buffering it
        <<ptr_field::8, rest::binary>> = data
        <<_prev_section::binary-size(ptr_field), section_bytes::binary>> = rest
        {<<>>, section_bytes}
      end
    end

    new_residue_state = Map.put(state.pid_residue, pid, new_residue)
    new_state = %{state | :pid_residue => new_residue_state}
    {buffer, new_state}
  end

  defp get_stream_type(type) do
    case type do
      0x01 -> :mpeg2v
      0x02 -> :mpeg2v
      0x03 -> :m1l2
      0x04 -> :m1l2
      0x0f -> :aac
      0x15 -> :id3
      0x1b -> :avc
      0x24 -> :hevc
      0x25 -> :hevc
      0x42 -> :avs
      0xea -> :vc1
      0x86 -> :scte35
      _    -> :others
    end
  end

  # return [{pid, stream_type}]
  defp get_stream(stream_info_payload) when is_binary(stream_info_payload) do
    get_stream(stream_info_payload, [])
  end

  defp get_stream(<<stream_type_id::8, _::3, pid::13, _::4, es_info_len::12, _descriptor::binary-size(es_info_len), rest::binary>>, streams) do
    stream_type = get_stream_type(stream_type_id)
    get_stream(rest, [{pid, stream_type} | streams])
  end

  defp get_stream(_dont_care, streams) do
    Enum.reverse(streams)
  end

  # return [{pid, pgm_num}]
  defp get_pgm(pat_payload) when is_binary(pat_payload) do
    get_pgm(pat_payload, [])
  end

  defp get_pgm(<<program_number::16, _reserved::3, pid::13, rest::binary>>, programs) do
    get_pgm(rest, [{pid, program_number} | programs])
  end

  defp get_pgm(dont_care, programs) when is_binary(dont_care) do
    Enum.reverse(programs)
  end

end

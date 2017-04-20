defmodule Exts.Printer do
  def ts_statistics_to_string(nil) do
    ""
  end

  def ts_statistics_to_string(stat) do
    "npkts: " <> Integer.to_string(stat.npkts) <> ", ccerrors: " <> Integer.to_string(stat.ccerrors)
  end

  def ts_stream_to_string(s) do
    "Stream: " <> Integer.to_string(s.pid) <> ", type: " <> Atom.to_string(s.type)
  end

  def ts_program_to_string(p) do
    "Program: " <> Integer.to_string(p.pgm_num) <> " (Pid: " <> Integer.to_string(p.pid) <> ")\n"
    <> "Pcr Pid: " <> Integer.to_string(p.pcr_pid)
  end

  def ts_state_to_string(state) do
    stream_pids = state.streams |> Enum.map(&(&1.pid))

    Enum.reduce(state.programs, "",
      fn (p, acc) ->
        acc <> ts_program_to_string(p) <> "\n" <>
          Enum.reduce(state.streams, "",
            fn (s, acc) ->
              cond do
                s.pmt_pid != p.pid -> acc
                True ->
                  acc
                  <> "\t" <> ts_stream_to_string(s) <> "\n"
                  <> "\t  " <> ts_statistics_to_string(state.statistics[s.pid]) <> "\n"
              end
            end
          )
        <> "\n"
      end
    ) <>
    # Printing for streams that is not associated with any program
    Enum.reduce(state.streams, "",
      fn (s, acc) ->
        cond do
          s.pmt_pid == -1 ->
            acc <> "\t" <> ts_stream_to_string(s)
            <> "\t  " <> ts_statistics_to_string(state.statistics[s.pid]) <> "\n"
          True -> acc
        end
      end
    ) <>
    # Finally, printing statistics for pids that is not a streams
    (state.statistics
    |> Map.values
    |> Enum.reduce("",
      fn (s, acc) ->
        cond do
          not s.pid in stream_pids ->
            acc <> "Pid: #{s.pid}, " <> ts_statistics_to_string(s) <> "\n"
          True -> acc
        end
      end
    ))
  end
end

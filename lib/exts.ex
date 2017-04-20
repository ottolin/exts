defmodule Exts do
  def main(args) do
    args
    |> OptionParser.parse(aliases: [m: :mcast, p: :port, i: :interface], switches: [port: :integer])
    |> run
  end

  defp run({[mcast: mcast, port: port, interface: interface], _, _}) do
    IO.puts "Listening to #{mcast}@#{port} via #{interface}"
    {:ok, addr} = mcast |> String.to_charlist |> :inet_parse.address
    {:ok, nic} = interface |> String.to_charlist |> :inet_parse.address
    {:ok, socket} = :gen_udp.open(port, [:binary, {:reuseaddr, true}, {:active, false}, {:recbuf, 16384000}, {:ip, addr}, {:multicast_if, nic}, {:add_membership, {addr, nic}}])
    # TODO: ssm?
    # {:ok, src} = :inet_parse.address(String.to_char_list("0.0.0.0"))
    # {:ok, socket} = :gen_udp.open(port, [:binary, {:reuseaddr, true}, {:active, false}, {:ip, addr}, {:multicast_if, nic}])

    # # prepare igmpv3 ssm using raw...
    # nicbin = nic |> :erlang.tuple_to_list |> :erlang.list_to_binary
    # gpbin = addr |> :erlang.tuple_to_list |> :erlang.list_to_binary
    # srcbin = src  |> :erlang.tuple_to_list |> :erlang.list_to_binary

    # bin = << gpbin::binary, nicbin::binary, srcbin::binary >>
    # :inet.setopts(socket, [{:raw, 0, 39, bin}])

    IO.puts "Socket created."
    IO.inspect socket

    stat_folder = "./udp-#{mcast}.stat"
    {:ok, log_server} = Exts.Callbacks.FileLogServer.start_link([{:output_folder, stat_folder}])
    {:ok, parser} = Exts.Transport.start_link([{:callback, {Exts.Callbacks.FileLogServer, log_server}}, {:summary_interval, 1000}])
    IO.puts "Start receiving..."
    udp_recv_loop(socket, parser)
  end

  defp run({[], [file], _}) do
    IO.puts "Parsing file: #{file}"
    if File.exists?(file) do
      stat_folder = Path.join(Path.dirname(file), Path.basename(file) <> ".stat")
      {:ok, log_server} = Exts.Callbacks.FileLogServer.start_link([{:output_folder, stat_folder}])
      {:ok, parser} = Exts.Transport.start_link([{:callback, {Exts.Callbacks.FileLogServer, log_server}}])

      File.stream!(file, [:read], 188 * 5000)
      |> Stream.each(fn buf -> Exts.Transport.feed(parser, buf) end)
      |> Stream.run

      Exts.Callbacks.FileLogServer.flush(log_server)
      IO.puts Exts.Transport.info(parser)
    else
      IO.puts "File not exist: #{file}"
    end
  end

  defp run(_) do
    usage()
  end

  defp usage do
    IO.puts("Usage:")
    IO.puts("\t<path_to_file> --- File mode")
    IO.puts("\t-m <multicast_address> -p <port> -i <interface> --- Udp mode")
  end

  defp udp_recv_loop(socket, parser) do
    {:ok, {_addr, _port, data}} = :gen_udp.recv(socket, 1316)
    Exts.Transport.feed(parser, data)
    udp_recv_loop(socket, parser)
  end
end

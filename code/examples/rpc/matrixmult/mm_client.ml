(* Test client. Starts one multiplication *)

open Printf

let main() =
  let host = ref "localhost" in
  let port = ref 2021 in
  let lrows = ref 1000 in
  let rcols = ref 1000 in
  let rrows = ref 1000 in
  Arg.parse
    [ "-host", Arg.Set_string host, 
      "<host>   Contact the multiplier at this host";

      "-port", Arg.Set_int port, 
      "<port>   Contact the multiplier at this port";

      "-size", Arg.Tuple [ Arg.Set_int lrows;
			   Arg.Set_int rcols;
			   Arg.Set_int rrows
			 ],
      "<P> <Q> <R>   Size of test: Multiply a PxR with a RxQ matrix"
    ]
    (fun arg -> raise(Arg.Bad("Bad argument: " ^ arg)))
    (sprintf "usage: %s <options>" Sys.argv.(0));

  let multiplier =
    Mm_proto_clnt.Multiplier.V1.create_client2
      (`Socket(Rpc.Tcp,
	       Rpc_client.Inet(!host,!port),
	       Rpc_client.default_socket_config)) in
  Mm_proto_clnt.Multiplier.V1.test_multiply 
    multiplier
    (!lrows, !rcols, !rrows)


let () =
  Netsys_signal.init();
  main()

open Printf

let urls =
  [ "https://www.wellsfargo.com/";
    "https://godirepo.camlcity.org/";
    "http://www.gerd-stolpmann.de";
    "https://broking.postbank.de/templates/index.jsp";
    "https://adwords.google.de/select/";
    "https://www.cortalconsors.de/";
    "https://www.collmex.de/cgi-bin/cgi.exe?35335,0,login";
    "https://www.comfi.com/reg/?l="
  ] ;;

(*
Uq_engines.Debug.enable := true;;
Netsys_tls.Debug.enable := true;;
Nethttp_client.Debug.enable := true;;
Nethttp_client.Convenience.http_verbose ~verbose_response_contents:true ();;
*)

let () =
  Nettls_gnutls.init();

  let errors = ref 0 in

  List.iter
    (fun url ->
       let t0 = Unix.time() in
       printf "URL %s: %!" url;
       ( try
	   let _ = Nethttp_client.Convenience.http_get url in ()
	 with
	   | error ->
	       printf "Error %s\n%!" (Netexn.to_string error);
	       incr errors
       );
       let t1 = Unix.time() in
       if t1 -. t0 > 10.0 then (
	 printf "TOO SLOW\n%!";
	 incr errors
       )
       else
	 printf "OK\n%!"
    )
    urls;

  printf "Errors: %d\n" !errors;
  if !errors > 0 then (
    printf "*** TEST FAILED!\n%!";
    exit 1
  )

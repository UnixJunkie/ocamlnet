(* $Id$
 * ----------------------------------------------------------------------
 *
 *)

(** Common types and exceptions *)

open Netnumber

type protocol =
    Tcp          (** means: stream-oriented connection *)
  | Udp;;        (** means: datagram exchange *)

type mode =
    Socket     (** classical server socket *)
  | BiPipe     (** server is endpoint of a bidirectional pipe *)

(* these are error conditions sent to the client: *)

type server_error =
    Unavailable_program                      (** accepted call! *)
  | Unavailable_version of (uint4 * uint4)   (** accepted call  *)
  | Unavailable_procedure                    (** accepted call  *)
  | Garbage                                  (** accepted call  *)
  | System_err                               (** accepted call  *)
  | Rpc_mismatch of (uint4 * uint4)          (** rejected call  *)
  | Auth_bad_cred                            (** rejected call  *)
  | Auth_rejected_cred                       (** rejected call  *)
  | Auth_bad_verf                            (** rejected call  *)
  | Auth_rejected_verf                       (** rejected call  *)
  | Auth_too_weak                            (** rejected call  *)
  | Auth_invalid_resp                        (** rejected call  *)
  | Auth_failed                              (** rejected call  *)
  | RPCSEC_GSS_credproblem                   (** rejected call  *)
  | RPCSEC_GSS_ctxproblem                    (** rejected call  *)
;;

val string_of_server_error : server_error -> string
  (** returns a string for debug purposes *)


exception Rpc_server of server_error;;
  (** an exception generated by the RPC server *)


exception Rpc_cannot_unpack of string;;
  (** RPC protocol error (bad data) *)

val create_inet_uaddr : Unix.inet_addr -> int -> string
  (** Create an universal address from an internet addr and a port *)

val parse_inet_uaddr : string -> (Unix.inet_addr * int)
  (** Parses an universal address and returns internet addr and port.
      Failure if not parsable.
   *)

val netid_of_inet_addr : Unix.inet_addr -> protocol -> string
  (** Get the netid for an Internet address *)

val sockaddr_of_uaddr : string -> string -> (Unix.sockaddr * protocol) option
  (** [sockaddr_of_uaddr netid uaddr]. Returns None for unknown netid *)

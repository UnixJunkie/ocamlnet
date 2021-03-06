(* $Id$ *)

(** Utility functions *)

type verbosity =
    [ `Name_only | `Name_abbrev_args | `Name_full_args ]
   (** How verbose the RPC ftrace is:
        - [`Name_only]: For each RPC call only the name is logged
        - [`Name_abbrev_args]: The name and the abbreviated argument list
          are logged
        - [`Name_full_args]: The name and the full argument list are logged
    *)

val string_of_request : 
      verbosity -> Rpc_program.t -> string -> Netxdr.xdr_value -> string
   (** Return the string representation of this call request *)

val string_of_response :
      verbosity -> Rpc_program.t -> string -> Netxdr.xdr_value -> string
   (** Return the string representation of this call response *)

val string_of_value :
      Netxdr.xdr_type_term -> Netxdr.xdr_value -> string
   (** Return a string representation of the value which must have the
       passed type
    *)

val hex_dump_m :
      Netsys_mem.memory -> int -> int -> string
val hex_dump_b :
      Bytes.t -> int -> int -> string
   (** Format the contents as hex sequence *)

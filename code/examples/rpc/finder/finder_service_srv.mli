(************************************************************
 * WARNING!
 *
 * This file is generated by ocamlrpcgen from the source file
 * finder_service.x
 *
 ************************************************************)
module Finder : sig
  module V1 : sig
    open Finder_service_aux
    val bind :
            ?program_number:Rtypes.uint4 ->
            ?version_number:Rtypes.uint4 ->
            proc_ping : (t_Finder'V1'ping'arg -> t_Finder'V1'ping'res) ->
            proc_find : (t_Finder'V1'find'arg -> t_Finder'V1'find'res) ->
            proc_lastquery : (t_Finder'V1'lastquery'arg ->
                              t_Finder'V1'lastquery'res) ->
            proc_shutdown : (t_Finder'V1'shutdown'arg ->
                             t_Finder'V1'shutdown'res) ->
            Rpc_server.t ->
            unit
    val bind_async :
            ?program_number:Rtypes.uint4 ->
            ?version_number:Rtypes.uint4 ->
            proc_ping : (Rpc_server.session ->
                         t_Finder'V1'ping'arg ->
                         (t_Finder'V1'ping'res -> unit) ->
                         unit) ->
            proc_find : (Rpc_server.session ->
                         t_Finder'V1'find'arg ->
                         (t_Finder'V1'find'res -> unit) ->
                         unit) ->
            proc_lastquery : (Rpc_server.session ->
                              t_Finder'V1'lastquery'arg ->
                              (t_Finder'V1'lastquery'res -> unit) ->
                              unit) ->
            proc_shutdown : (Rpc_server.session ->
                             t_Finder'V1'shutdown'arg ->
                             (t_Finder'V1'shutdown'res -> unit) ->
                             unit) ->
            Rpc_server.t ->
            unit
    end
  
end



(* $Id$ *)

(** RPC proxies *)

(** The [Rpc_proxy] module provides an improved reliability layer on
    top of {!Rpc_client}. This layer especially features:
     - automatic connection management: TCP connections are started
       and terminated as needed
     - multiple connections can be held in parallel to a remote
       server to increase concurrency on the server side
     - failover to other servers when the orignal servers time out
     - support for an initial ping at connection establishment time
       to test the availability of the connection
     - retransmission of idempotent RPC calls
 
    Proxies can only handle stream connections (TCP and Unix Domain).
    Also, the remote endpoints must already be specified by socket
    addresses. (No portmapper and other indirect lookup methods.)

    Ideally, RPC calls look like local procedure calls. Because of
    failures and timeouts, they are fundamentally less reliable.
    The proxy layer adds some techniques that improve the reliability
    again. However, the same level as local calls provide cannot be reached.

    In particular, network errors and timeouts are normally not hidden
    from the user. The semantics of RPC calls may change when they are
    repeated, especially when this is done on alternate network connections.
    The simple case of idempotent procedures is better handled, however:
    By definition, idempotent procedures can be again called without
    changing the semantics. The proxy layer supports this.

    The proxy can be used together with the language mapping layer
    generated by [ocamlrpcgen]. Just do

    {[ module M = F_clnt.Make'P(Rpc_proxy.ManagedClient) ]}

    to get language-mapped procedure calls (where [F_clnt] is the generated
    client module, and [P] is the name of the program).
 *)

module ReliabilityCache : sig
  (** The reliability cache stores information about the availability
      of remote servers. The managed clients put information about
      recent failures into the cache.

      It is advantegeous to have only one cache per process, because
      this maximizes the usefulness. The cache is thread-safe.

      A server endpoint is disabled when too many errors occur in
      sequence. For a disabled endpoint the functions [host_is_enabled]
      and/or [sockaddr_is_enabled] return [false]. The endpoint is
      automatically enabled again after some timeout; this is initially
      [disable_timeout_min], but is increased exponentially until
      [disable_timeout_max] when further errors occur.

      Independently of this machinery the functions [host_is_enabled]
      and [sockaddr_is_enabled] may also return [false] when an
      external availability checker says that the endpoint is down.
      This information is not entered into the cache, and will also
      not trigger the disable timeout. Instead, the hook function
      getting the availability will be simply called again.
   *)

  type rcache
    (** The cache *)

  type rcache_policy =
      [ `Independent
      | `Failing_port_disables_host of int
      | `Any_failing_port_disables_host
      | `None
      ]
    (** How failures of individual ports are interpreted:
        - [`Independent]: When a connection to a remote port repeatedly fails, 
          only this port is disabled
        - [`Failing_port_disables_host p]: When a connection to the TCP
          port [p] repeatedly fails, the whole remote host is disabled.
          Other ports do not disable the host, but are treated as in 
          [`Independent].
        - [`Any_failing_port_disables_host]: When a connection to any TCP
          port repeatedly fails, the whole remote host is disabled
        - [`None]: Nothing is disabled

        Note that the [rcache_availability] hook is not affected by the
        policy; this hook is called anyway. The policy only determines
        how the internal error counter is interpreted.
     *)

  type rcache_config =
      { rcache_policy : rcache_policy;   (** The policy, see above *)
	rcache_disable_timeout_min : float;  (** For how long ports and hosts 
                                             are disabled *)
	rcache_disable_timeout_max : float;  (** For how long ports and hosts 
                                             are disabled at most *)
	rcache_threshold : int;   (** How many errors are required 
                                      for disabling a port *)
	rcache_availability : rcache -> Unix.sockaddr -> bool;  (** External
            availability checker. Called  by [sockaddr_is_enabled] before
            the result is calculated *)
      }

  val create_rcache_config : ?policy:rcache_policy -> 
                             ?disable_timeout_min:float ->
                             ?disable_timeout_max:float ->
                             ?threshold:int ->
                             ?availability:(rcache -> Unix.sockaddr -> bool) ->
                             unit -> rcache_config
    (** Create a config record. The optional arguments set the config
        components with the same name. The arguments default to:
         - [policy = `None]
         - [disable_timeout_min = 1.0]
         - [disable_timeout_max = 64.0]
         - [threshold = 1]
         - [availability = fun _ _ -> true]
     *)

  val create_rcache : rcache_config -> rcache
    (** Creates a new cache object. The same cache can be used by several
        managed clients, even by totally unrelated ones
     *)

  val rcache_config : rcache -> rcache_config
    (** Return the config *)

  val global_rcache_config : unit -> rcache_config
    (** Returns the global config:
         - [policy = `Independent]
         - [disable_timeout_min = 1.0]
         - [disable_timeout_max = 1.0]
         - [threshold = 1]
         - [availability = fun _ _ -> true]
     *)

  val set_global_rcache_config : rcache_config -> unit
    (** Sets the new global config. This is only possible as long as
        neither [default_global_config] nor [global_rcache] have been called.
     *)

  val global_rcache : unit -> rcache
    (** The global cache. Initially, this cache has the default config.
        It is possible to change the default config before using the
        global cache for the first time.
     *)

  val derive_rcache : rcache -> rcache_config -> rcache
    (** [derive_cache parent config]: Returns a new cache that shares the
        error counters with [parent]. The interpretation of the counters,
        however, may be differently configured in [config].

        Because it is advantageous to share the error information as much
        as possible, the recommended way to create a new cache object is
        to derive it from the global cache.

        What [derive_rcache] actually does (and this is not yet
        optimal): Any [incr] and [reset] of an error counter is also
        forwarded to the parent cache. The tests whether hosts and ports
        are enabled do an AND of the results for the cache and its parent
        (i.e. both must be ok to enable). This allows some information
        sharing, but only in vertical direction.
     *)

  val incr_rcache_error_counter : rcache -> Unix.sockaddr -> unit
    (** Increase the error counter for this sockaddr. If the threshold
        is reached and there is a disable policy, the sockaddr will be disabled.

        This function is to be called after an RPC call times out, or
        runs into a socket error.
     *)

  val reset_rcache_error_counter : rcache -> Unix.sockaddr -> unit
    (** Reset the error counter for this sockaddr. If disabled, the
        sockaddr is set to enabled again.

        This function is to be called when an RPC call is successful.
     *)

  val sockaddr_is_enabled : rcache -> Unix.sockaddr -> bool
    (** Returns whether the sockaddr is enabled. This also calls the
        [rcache_availability] hook.
     *)

  val host_is_enabled : rcache -> Unix.inet_addr -> bool
    (** Returns whether the host is enabled *)

end

module ManagedClient : sig
  (** Managed clients are {!Rpc_client} clients with the ability to
      reconnect in the case of errors. 

      Additional features:
       - they can also be disabled, either based on a  time criterion or
         a customizable hook. This encodes the assumption that failing
         servers need some time to recover
       - unused connections are closed (driven by a timeout)
       - support for the initial ping after establishing the connection

      Initial pings are useful to test whether the connection is
      really working. Servers normally accept new TCP connections without
      knowing whether there are resources for processing the connections
      (i.e. whether there is a process or thread waiting for serving
      it). Because of this, the client cannot assume that the TCP
      connection is really up only because the [connect] system call
      said the connection is there. The initial ping fixes this problem:
      The null procedure is once called after the TCP connection has
      been established. Only when this works the client believes the
      connection is really up. It is required that [mclient_programs]
      is configured with at least one program, and this program must
      have a procedure number 0 of type [void -> void].

      In multi-threaded programs, threads must not share managed clients.
   *)
 
  type mclient
    (** A managed client *)

  type mclient_config =
      { mclient_rcache : ReliabilityCache.rcache;  (** The rcache *)
	mclient_socket_config : Rpc_client.socket_config;
	  (** The socket configuration *)
	mclient_idle_timeout : float;
	  (** After how many seconds unused connections are closed.
              A negative value means never. 0 means immediately. A positive
              value is a point in time in the future.
	   *)
	mclient_programs : Rpc_program.t list;
	  (** The programs to bind *)
	mclient_msg_timeout : float;
	  (** After how many seconds the reply must have been arrived.
              A negative value means there is no timeout. 0 means immediately. 
              A positive
              value is a point in time in the future.
	   *)
	mclient_msg_timeout_is_fatal : bool;
	  (** Whether a message timeout is to be considered as fatal error
              (the client is shut down, and the error counter for the endpoint
              is increased)
	   *)
	mclient_exception_handler : (exn -> unit) option;
	  (** Whether to call {!Rpc_client.set_exception_handler} *)
	mclient_auth_methods : Rpc_client.auth_method list;
	  (** Set these authentication methods in the client *)
	mclient_initial_ping : bool;
	  (** Whether to call procedure 0 of the first program after
              connection establishment (see comments above)
	   *)
	mclient_max_response_length : int option;
	  (** The maximum response length. See 
              {!Rpc_client.set_max_response_length}.
	   *)
      }

  exception Service_unavailable
    (** Procedure calls may end with this exception when the reliability
        cache disables the service
     *)

  val create_mclient_config : ?rcache:ReliabilityCache.rcache ->
                              ?socket_config:Rpc_client.socket_config ->
                              ?idle_timeout:float ->
                              ?programs:Rpc_program.t list ->
                              ?msg_timeout:float ->
                              ?msg_timeout_is_fatal:bool ->
                              ?exception_handler:(exn -> unit) ->
                              ?auth_methods:Rpc_client.auth_method list ->
                              ?initial_ping:bool ->
                              ?max_response_length:int ->
                              unit -> mclient_config
    (** Create a config record. The optional arguments set the config
        components with the same name. The defaults are:
         - [rcache]: Use the global reliability cache
         - [socket_config]: {!Rpc_client.default_socket_config}
         - [programs]: The empty list. It is very advisable to fill this!
         - [msg_timeout]: (-1), i.e. none
         - [msg_timeout_is_fatal]: false
         - [exception_handler]: None
         - [auth_methods]: empty list
         - [initial_ping]: false
         - [max_response_length]: None
     *)

  val create_mclient : mclient_config -> 
                       Rpc_client.connector ->
                       Unixqueue.event_system ->
                         mclient
    (** Create a managed client for this config connecting to this
        connector. Only [Internet] and [Unix] connectors are supported.
     *)

  type state = [ `Down | `Connecting | `Up of Unix.sockaddr option]
      (** The state:
           - [`Down]: The initial state, and also reached after a socket
             error, or after one of the shutdown functions is called.
             Although [`Down], there might still some cleanup to do.
             When RPC functions are called, the client is automatically
             revived.
           - [`Connecting]: This state is used while the initial ping is
             done. It does not reflect whether the client is really 
             TCP-connected. Without initial ping, this state cannot occur.
           - [`Up s]: The client is (so far known) up and can be used.
             [s] is the socket address of the local socket
       *)

  val mclient_state : mclient -> state
    (** Get the state *)

  val pending_calls : mclient -> int
    (** Returns the number of pending calls *)

  val event_system : mclient -> Unixqueue.event_system
    (** Return the event system *)

  val shut_down : mclient -> unit
  val sync_shutdown : mclient -> unit
  val trigger_shutdown : mclient -> (unit -> unit) -> unit
    (** Shut down the managed client. See the corresponding functions
        {!Rpc_client.shut_down}, {!Rpc_client.sync_shutdown}, and
        {!Rpc_client.trigger_shutdown}
     *)

  val record_unavailability : mclient -> unit
    (** Increases the error counter in the reliability cache for this
        connection. The only effect can be that the error counter
        exceeds the [rcache_threshold] so that the server endpoint
        is disabled for some time. However, this only affects new 
        connections, not existing ones.

        For a stricter interpretation of errors see 
        [enforce_unavailability].

        The error counter is increased anyway when a socket error
        happens, or an RPC call times out and [msg_timeout_is_fatal]
        is set. This function can be used to also interpret other
        misbehaviors as fatal errors.
     *)
    (* This is a strange function. Maybe it should go away. One could
       call it after a successful RPC call when the result of this call
       indicates that the server is not good enough for further use
       (although it is still able to respond). However, after a successful
       RPC the error counter is reset, and this cannot be prevented by
       this function (too late)
     *)

  val enforce_unavailability : mclient -> unit
    (** Enforces that all pending procedure calls get the
        [Service_unavailable] exception, and that the client is shut down.
        The background is this: When the reliability cache discovers an
        unavailable port or host, only the new call is stopped with this
        exception, but older calls remain unaffected. This function
        can be used to change the policy, and to stop even pending calls.

        The difference to [trigger_shutdown] is that the pending RPC
        calls get the exception [Service_unavailable] instead of
        {!Rpc_client.Message_lost}, and that it is enforced that the
        shutdown is recorded as fatal error in the reliability cache.
     *)

  val set_batch_call : mclient -> unit
    (** The next call is a batch call. See {!Rpc_client.set_batch_call} *)

  val compare : mclient -> mclient -> int
    (** [ManagedClient] can be used with [Set.Make] and [Map.Make] *)

  include Rpc_client.USE_CLIENT with type t = mclient
    (** We implement the [USE_CLIENT] interface for calling procedures *)
end

module ManagedSet : sig
  (** Manages a set of clients *)

  type mset
    (** a managed set *)

  type mset_policy =
      [ `Failover | `Balance_load ]
	(** Sets in which order managed clients are picked from the 
            [services] array passed to [create_mset]:
             - [`Failover]: Picks an element from the first service
               in [services] that is enabled and has free capacity.
               That means that the first service is preferred until it is
               maxed out or it fails, then the second service is preferred,
               and so on.
             - [`Balance_load]: Picks an element from the service in 
               [services] that is enabled and has the lowest load.
	 *)

  type mset_config =
      { mset_mclient_config : ManagedClient.mclient_config;  
	   (** The mclient config *)
	mset_policy : mset_policy;
           (** The policy *)
	mset_pending_calls_max : int;
	  (** When an mclient processes this number of calls at the same time,
              it is considered as fully busy. (Value must by > 0).
	   *)
	mset_pending_calls_norm : int;
	  (** When an mclient processes less than this number of calls,
              its load is considered as too light, and it is tried to put
              more load on this client before opening another one
	   *)
	mset_idempotent_max : int;
	  (** How often idempotent procedures may be tried to be called.
              A negative value means infinite.
	   *)
        mset_idempotent_wait : float;
          (** Wait this number of seconds before trying again *)
      }

  exception Cluster_service_unavailable
    (** Raised by [mset_pick] when no available endpoint can be found,
        or all available endpoints have reached their maximum load.
     *)

  val create_mset_config : ?mclient_config:ManagedClient.mclient_config ->
                           ?policy:mset_policy ->
                           ?pending_calls_max:int ->
                           ?pending_calls_norm:int ->
                           ?idempotent_max:int ->
                           ?idempotent_wait:float ->
                           unit -> mset_config
    (** Create a config record. The optional arguments set the config
        components with the same name. The defaults are:
         - [mclient_config]: The default mclient config
         - [policy]: [`Balance_load]
         - [pending_calls_max]: [max_int]
         - [pending_calls_norm]: 1
         - [idempotent_max]: 3
         - [idempotent_wait]: 5.0
     *)

  val create_mset : mset_config ->
                    (Rpc_client.connector * int) array ->
                    Unixqueue.event_system ->
                    mset
    (** [create_mset config services]: The mset is created with [config],
        and the [services] array describes which ports are available,
        and how often each port may be contacted (i.e. max number of
        connections).
     *)

  val mset_pick : ?from:int list -> mset -> ManagedClient.mclient * int
    (** Pick an mclient for another call, or raise [Cluster_service_unavailable].
        The returned int is the index in the [mset_services] array.

        If [from] is given, not all specified mclients qualify for this
        call. In [from] one can pass a list of indexes pointing into
        the [mset_services] array, and only from these mclients the 
        mclient is picked. For [`Failover] policies, the order given
        in [from] is respected, and the mclients are checked from left
        to right.
     *)

  val mset_services : mset -> (Rpc_client.connector * int) array
    (** Returns the service array *)

  val mset_load : mset -> int array
    (** Returns the number of pending calls per service *)

  val event_system : mset -> Unixqueue.event_system
    (** Return the event system *)

  val shut_down : mset -> unit
  val sync_shutdown : mset -> unit
  val trigger_shutdown : mset -> (unit -> unit) -> unit
    (** Shut down the managed set. See the corresponding functions
        {!Rpc_client.shut_down}, {!Rpc_client.sync_shutdown}, and
        {!Rpc_client.trigger_shutdown}
     *)

  val idempotent_async_call :
       ?from:int list -> 
       mset -> 
       (ManagedClient.mclient -> 'a -> ((unit -> 'b) -> unit) -> unit) ->
       'a ->
       ((unit -> 'b) -> unit) -> 
         unit
    (** [idempotent_async_call
           mset async_call arg emit]: Picks a new
        [mclient] and calls [async_call mclient arg emit].
        If the call leads to a fatal error, a new [mclient]
        is picked, and the call is repeated. In total, the call may be
        tried [mset_idempotent_max] times. It is recommended to set
        [rcache_threshold] to 1 when using this function because this
        enforces that a different mclient is picked when the first one
        fails.

        Note that a timeout is not considered as a fatal error by default;
        one has to enable that by setting [mclient_msg_timeout_is_fatal].

        Note that this form of function is compatible with the 
        generated [foo'async] functions of the language mapping.

        [from] has the same meaning as in [mset_pick].
     *)

  val idempotent_sync_call :
       ?from:int list -> 
       mset -> 
       (ManagedClient.mclient -> 'a -> ((unit -> 'b) -> unit) -> unit) ->
       'a ->
       'b
    (** Synchronized version. Note that you have to pass an asynchronous
        function as second argument. The result is synchronous, however.
     *)

end

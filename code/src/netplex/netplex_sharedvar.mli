(* $Id$ *)

(** Netplex-wide variables *)

(** This plugin allows to have Netplex-global variables that can be read
    and written by all components. These variables are useful to communicate
    names and other small pieces of information across the whole Netplex.
    For instance, one component could allocate a shared memory object, and
    put its name into a variable to make it known to other components.

    This implementation works in both multi-processing and
    multi-threading netplex environments. It is, however, not very
    fast, because the variables live in the controller, and the
    access operations are realized by RPC's. It is good
    enough when these operations are only infrequently called, e.g. in
    the post-start and pre-finish processor callbacks.

    Furthermore, note that it is unwise to put large values into
    variables when using them in multi-processing contexts. The controller
    process is also the parent process of all [fork]ed children, and
    when a lot of memory is allocated in the controller, all
    this memory needs to be copied when the [fork] is done. As workaround,
    put such values into temporary files, and only pass the names of the
    files around via variables.
 *)

open Netplex_types

val plugin : plugin
  (** To enable shared variables, call the controller's [add_plugin] method
      with this object as argument. This can e.g. be done in the
      [post_add_hook] of the processor.
   *)



(** The folloing functions can {b only} be invoked in container
    contexts. Outside of such a context the exception
    {!Netplex_cenv.Not_in_container_thread} is raised. 
 *)

val create_var : ?own:bool -> ?ro:bool -> string -> bool
  (** Create the variable with the passed name with an empty string as
      initial value. If the creation is possible (i.e. the variable did
      not exist already), the function returns [true], otherwise 
      the already existing variable is left modified, and [false] is
      passed back. By default, the variable can be modified and deleted
      by any other container. Two options allow you to change that:

      - [own]: If true, the created variable is owned by the calling
        socket service. Only the caller can delete it, and when the 
        last component of the socket service terminates, the variable is
        automatically deleted.
      - [ro]: if true, only the owner can set the value

      Variable names are global to the whole netplex system. By convention,
      these names are formed like ["service_name.local_name"], i.e. they
      are prefixed by the socket service to which they refer.
   *)

val delete_var : string -> bool
  (** [delete_var name]: Deletes the variable [name]. Returns [true] if
      the deletion could be carried out, and [false] when the variable
      does not exist, or the container does not have permission to delete
      the variable.
   *)

val set_value : string -> string -> bool
  (** [set_value name value]: Sets the variable [name] to [value]. This
      is only possible when the variable exists, and is writable.
      Returns [true] if the function is successful, and [false] when
      the variable does not exist, or the container does not have permission 
      to modify the variable.
   *)

val get_value : string -> string option
  (** [get_value name]: Gets the value of the variable [name]. If the
      variable does not exist, [None] is returned.
   *)

val wait_for_value : string -> string option
  (** [wait_for_value name]: If the variable exists and [set_value] has
      already been called at least once, the current value is returned. 
      If the variable exists, but [set_value] has not yet been called at all,
      the function waits until [set_value] is called, and returns the value
      set then. If the variable does not exist, the function immediately
      returns [None].

      An ongoing wait is interrupted when the variable is deleted. In this
      case [None] is returned.
   *)

val get_lazily : string -> (unit -> string) -> string option
  (** [get_lazily name f]: Uses the variable [name] to ensure that [f]
      is only invoked when [get_lazily] is called for the first time,
      and that the value stored in the variable is returned the
      next times. This works from whatever component [get_lazily]
      is called.

      If [f()] raises an exception, the exception is suppressed, and
      [None] is returned as result of [get_lazily]. Exceptions are not
      stored in the variable, so the next time [get_lazily] is called
      it is again tried to compute the value of [f()]. If you want to
      catch the exception this must done in the body of [f].

      No provisions are taken to delete the variable. If [delete_var]
      is called by user code (which is allowed at any time), and
      [get_lazily] is called again, the lazy value will again be computed.
   *)


(** Example code:

    Here, one randomly chosen container computes [precious_value], and
    makes it available to all others, so the other container can simply
    grab the value. This is similar to what [get_lazily] does internally:

    {[
      let get_precious_value() =
        let container = Netplex_cenv.self_cont() in
        let var_name = "my_service.precious" in
        if Netplex_sharedvar.create_var var_name then (
          let precious_value = 
            try ...    (* some costly computation *)
            with exn ->
              ignore(Netplex_sharedvar.delete_var var_name);
              raise exn in
          let b = Netplex_sharedvar.set_value var_name precious_value in
          assert b;
          precious_value
        )
        else (
          match Netplex_sharedvar.wait_for_value var_name with
           | Some v -> v
           | None -> failwith "get_precious_value"
                       (* or do plan B, e.g. compute the value *)
        )
    ]}

    We don't do anything here for deleting the value when it is no longer
    needed. Finding a criterion for that is very application-specific. 
    If the variable can be thought as being another service endpoint
    of a socket service, it is a good idea to acquire the ownership
    (by passing [~own:true] to [create_var]), so the variable is automatically
    deleted when the socket service stops.

    Of course, the plugin must be enabled, e.g. by overriding the 
    [post_add_hook] processor hook:

   {[ 
    method post_add_hook sockserv ctrl =
      ctrl # add_plugin Netplex_sharedvar.plugin
   ]}

 *)

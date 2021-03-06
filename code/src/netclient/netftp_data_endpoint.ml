(* $Id$ *)

open Netchannels
open Netconversion
open Uq_engines
open Uq_engines.Operators   (* ++, >>, eps_e *)
open Printf

exception Ftp_data_protocol_error

class type out_record_channel =
object
  inherit Netchannels.out_obj_channel
  method output_eor : unit -> unit
end

class type in_record_channel =
object
  inherit Netchannels.in_obj_channel
  method input_eor : unit -> unit
end

type local_receiver =
    [ `File_structure of Netchannels.out_obj_channel
    | `Record_structure of out_record_channel
    ]

type local_sender =
    [ `File_structure of Netchannels.in_obj_channel
    | `Record_structure of in_record_channel
    ]

type transmission_mode =
    [ `Stream_mode
    | `Block_mode
    ]

type descr_state =
    [ `Clean
    | `Transfer_in_progress
    | `Down
    ]

type text_data_repr =
    [ `ASCII      of Netconversion.encoding
    | `ASCII_unix of Netconversion.encoding
    | `EBCDIC     of Netconversion.encoding
    ]

type ftp_data_prot =
  [ `C | `S | `E | `P ]


type ftp_protector =
    { ftp_wrap_limit : unit -> int;
      ftp_wrap_s : string -> string;
      ftp_wrap_m : Netsys_types.memory -> Netsys_types.memory -> int;
      ftp_unwrap_s : string -> string;
      ftp_unwrap_m : Netsys_types.memory -> Netsys_types.memory -> int;
      ftp_prot_level : ftp_data_prot;
      ftp_close : unit -> unit;
      mutable ftp_gssapi_props : Netsys_gssapi.client_props option;
      mutable ftp_auth_loop : bool;
    }

class write_out_record_channel 
        ~(repr : text_data_repr) (out : out_obj_channel) =
  let eor_s = 
    match repr with
	`ASCII _ ->      "\013\010"  (* CR/LF *)
      | `ASCII_unix _ -> "\010"      (* LF *)
      | `EBCDIC _ ->     "\021"      (* NEL *)
  in
object(self)
  val mutable last_eor_pos = 0

  method output = out # output
  method flush = out # flush
  method pos_out = out # pos_out

  method output_char = out # output_char
  method output_string = out # output_string
  method output_byte = out # output_byte
  method output_bytes = out # output_bytes
  method output_buffer = out # output_buffer
  method output_channel = out # output_channel
  method really_output = out # really_output
  method really_output_string = out # really_output_string

  method output_eor() =
    out # output_string eor_s;
    last_eor_pos <- out # pos_out

  method close_out() =
    if out#pos_out > last_eor_pos then
      out # output_string eor_s;
    out # close_out();
end ;;


class read_in_record_channel 
        ~(repr : text_data_repr) (ch : in_obj_channel) =
  let eor_s = 
    match repr with
	`ASCII _ ->      "\013\010"  (* CR/LF *)
      | `ASCII_unix _ -> "\010"      (* LF *)
      | `EBCDIC _ ->     "\021"      (* NEL *)
  in
  let buffer_size = 4096 in
object(self)
  inherit Netchannels.augment_raw_in_channel

  val mutable buf = Netbuffer.create buffer_size
  val mutable eof = false
  val mutable bufrecend = None  (* Position of the EOL sequence, if found *)
  val mutable reclen = 0        (* Counter for length of record *)
  val mutable closed = false

  method private refill() =
    (* Fill buffer with at least one further character, or set [eof] *)
    try
      let n = Netbuffer.add_inplace buf ch#input in (* or End_of_file *)
      if n = 0 then raise Sys_blocked_io;
      self # set_bufrecend()
    with
	End_of_file ->
	  eof <- true


  method private set_bufrecend() =
    let eor_0 = eor_s.[0] in
    try
      if bufrecend <> None then raise Not_found;  (* ... not interested! *)
      let k = Netbuffer.index_from buf 0 eor_0 in  (* or Not_found *)
      if k + String.length eor_s > Netbuffer.length buf then 
	raise Not_found;
      if Netbuffer.sub buf k (String.length eor_s) <> eor_s then
	raise Not_found;
      (* Found EOR at position k: *)
      bufrecend <- Some k
    with
	Not_found -> 
	  ()


  method input s p l =
    if closed then raise Netchannels.Closed_channel;
    let m =
      match bufrecend with
	  None   when not eof -> Netbuffer.length buf - String.length eor_s + 1
	| None   when eof     -> Netbuffer.length buf
	| None                -> assert false (* to keep the compiler happy *)
	| Some n              -> n in
    let l' = min m l in
    if l > 0 && l' = 0 && bufrecend <> None then
      raise End_of_file;  (* meaning: end of record *)
    if l > 0 && l' = 0 && eof then
      raise End_of_file;  (* real EOF *)
    if l > 0 && l' = 0 then (
      self # refill();
      self # input s p l
    )
    else if l' > 0 then (
      Netbuffer.blit buf 0 s p l';
      Netbuffer.delete buf 0 l';
      ( match bufrecend with
	    None -> ()
	  | Some n -> bufrecend <- Some (n - l')
      );
      reclen <- reclen + l';
      l'
    )
    else 0

  method input_eor() =
    if closed then raise Netchannels.Closed_channel;
    (* Skip to EOR *)
    let m, found_eor =
      match bufrecend with
	  None   when not eof -> 
	    (Netbuffer.length buf - String.length eor_s + 1, false)
	| None   when eof     -> 
	    (Netbuffer.length buf, true)
	| None ->  (* to keep the compiler happy *)
	    assert false
	| Some n              -> 
	    (n, true) in
    Netbuffer.delete buf 0 m;
    if not found_eor then (
      self # refill();
      self # input_eor()
    )
    else (
      (* We are at EOR or EOF *)
      if eof && reclen <> 0 then (
	reclen <- 0;
	(* Don't raise End_of_file! *)
      )
      else if eof then
	raise End_of_file
      else (
	Netbuffer.delete buf 0 (String.length eor_s);
	reclen <- 0;
	bufrecend <- None;     (* Otherwise set_bufreclen won't work *)
	self # set_bufrecend()
      )
    )


  method close_in () =
    if not closed then (
      buf <- Netbuffer.create 1;   (* release memory *)
      closed <- true;
      ch # close_in()
    )

  method pos_in =
    if closed then raise Netchannels.Closed_channel;
    ch # pos_in - Netbuffer.length buf

  method input_line() =
    let line = Buffer.create 256 in
    let line_ch = new Netchannels.output_buffer line in
    line_ch # output_channel (self : # in_obj_channel :> in_obj_channel);
    Buffer.contents line

end ;;


class fake_out_record_channel (out : out_obj_channel) =
  (* Makes an out_record_channel from an out_obj_channel, but ignores
   * record boundaries
   *)
object(self)
  method output = out # output
  method flush = out # flush
  method pos_out = out # pos_out
  method close_out = out # close_out

  method output_char = out # output_char
  method output_string = out # output_string
  method output_byte = out # output_byte
  method output_bytes = out # output_bytes
  method output_buffer = out # output_buffer
  method output_channel = out # output_channel
  method really_output = out # really_output
  method really_output_string = out # really_output_string

  method output_eor() : unit =
    ()

end ;;


class fake_in_record_channel (ch : in_obj_channel) =
  (* Makes an in_record_channel from an in_obj_channel, but actually
   * raises End_of_file when a record boundary is tried to read.
   *
   * Note that this is a violation of the spec of in_record_channel,
   * as there is no empty EOF record. However, the block_record_writer
   * processes this as intended, no EOR sequence is sent at all.
   *)
object(self)
  method input = ch # input
  method pos_in = ch # pos_in
  method close_in = ch # close_in

  method input_char = ch # input_char
  method input_byte = ch # input_byte
  method input_line = ch # input_line
  method really_input = ch # really_input
  method really_input_string = ch # really_input_string

  method input_eor() : unit =
    raise End_of_file

end ;;


class data_converter ~(fromrepr : text_data_repr) ~(torepr : text_data_repr) =
  let from_enc =
    match fromrepr with
	`ASCII e      -> e
      | `ASCII_unix e -> e
      | `EBCDIC e     -> e
  in
  let to_enc_base =
    match torepr with
	`ASCII e      -> e
      | `ASCII_unix e -> e
      | `EBCDIC e     -> e
  in
  let to_enc = `Enc_subset(to_enc_base, 
			   fun k -> k <> 10 && k <> 13 && k <> 0x85) in
  (* The Unicode chars 10, 13, and 0x85 are the possible line separators. 
   * (0x85 is the Unicode char corresponding to EBCDIC 21.)
   *)
  let subst =
    (* CR is always discarded *)
    match torepr with
	`ASCII e      -> fun p -> if p = 10 || p = 0x85 then "\013\010" else ""
      | `ASCII_unix e -> fun p -> if p = 10 || p = 0x85 then "\010" else ""
      | `EBCDIC e     -> fun p -> if p = 10 || p = 0x85 then "\021" else ""
  in
  conversion_pipe ~subst ~in_enc:from_enc ~out_enc:to_enc ()
;;


class in_buffer 
        ?(onclose = fun () -> ()) 
	?(ondata = fun() -> ())
	~(buf:Netbuffer.t)
        () : Uq_engines.async_out_channel =
  (* This implementation is not asynchronous as [can_output] is always [true],
   * but we match this signature.
   *)
object(self)
  val mutable pos = 0

  method output s p l =
    let n =
      Netbuffer.add_inplace 
	buf 
	(fun s' p' l' ->
	   let ll = min l l' in
	   Bytes.blit s p s' p' ll;
	   ll
	) in
    pos <- pos + n;
(*
    prerr_endline "OUTPUT:";
    for i = p to p+n-1 do
      match s.[i] with
	  '\033'..'\126' ->
	    prerr_string (String.make 1 s.[i] ^ " ")
	| c ->
	    prerr_string (string_of_int (Char.code c) ^ " ")
    done;
    prerr_endline "";
 *)
    if n>0 then ondata();
    n

  method pos_out = pos

  method flush() = ()

  method close_out() = 
    onclose()
      
  method can_output = true

  method request_notification f = ()
    (* No need to implement this method as [can_output] never changes its
     * value
     *)

end


class stream_file_reader 
        ?(onclose = fun () -> ()) 
	?(ondata = fun() -> ())
	(out : out_obj_channel) : async_out_channel =
  (* An async_out_channel that forwards data to an out_obj_channel without
   * any conversion
   *
   * [onclose] is called when the real EOF is found in the stream, which
   * is also the logical EOF.
   *
   * [ondata] is called when [self#output] accepts at least one byte
   *)
object(self)
  val mutable closed = false

  method output s p l = 
    let n = out # output s p l in
    if n > 0 then ondata();
    n

  method close_out () = 
    if not closed then (
      out # close_out();
      closed <- true;
      onclose()
    )

  method flush = out # flush
  method pos_out = out # pos_out

  method can_output = true

  method request_notification f = ()
    (* No need to implement this method as [can_output] never changes its
     * value
     *)
end ;;


class stream_file_writer 
        ?(onclose = fun () -> ()) 
	?(ondata = fun() -> ())
	(ch : in_obj_channel) : async_in_channel =
  (* An async_in_channel reading data from an in_obj_channel without
   * any conversion
   *
   * [onclose] is called when the real EOF is found in the stream, which
   * is also the logical EOF.
   *
   * [ondata] is called when [self#input] accepts at least one byte,
   * or raises End_of_file.
   *)
object(self)
  val mutable closed = false

  method input s p l = 
    try
      let n = ch # input s p l in
      if n > 0 then ondata();
      n
    with
	End_of_file as x -> ondata(); raise x

  method close_in () = 
    if not closed then (
      ch # close_in();
      closed <- true;
      onclose();
    )


  method pos_in = ch # pos_in

  method can_input = true

  method request_notification f = ()
    (* No need to implement this method as [can_input] never changes its
     * value
     *)
end ;;


class stream_record_reader
        ?(onclose = fun () -> ()) 
	?(ondata = fun() -> ())
	?(commit = ref (fun () -> ()))
	(out : out_record_channel) =
  (* An async_out_channel that recognizes escape sequences, and forwards
   * the decoded data to an out_record_channel
   * 
   * Escape sequences:
   * 0xff 0x01: EOR
   * 0xff 0x02: EOF
   * 0xff 0x03: EOR + EOF
   * 0xff 0xff: The byte 0xff
   *
   * [onclose] is called when the logical EOF is found in the stream.
   *
   * [ondata] is called when [self#output] accepts at least one byte
   * 
   * [commit] is initialized to [self#commit].
   *)
  let buf = Netbuffer.create 512 in
  let local_onclose = ref (fun () -> ()) in  (* assigned in initializer *)
  let local_ondata  = ref (fun () -> ()) in
object(self)
  inherit
    in_buffer 
      ~onclose:(fun () -> !local_onclose()) 
      ~ondata:(fun () -> !local_ondata()) 
      ~buf ()

  val mutable eof_seen = false

  initializer
    local_onclose := self # check_eof;
    local_ondata  := self # forward;
    commit := self # commit

  method private forward() =
    (* Scan the contents of [buf] for escape sequences. A 0xff as last byte
     * of the buffer does not count, as it is expected to be followed by
     * a regular second byte, but we do not know yet which.
     *)
    let p = ref 0 in   (* Position in [buf] *)
    let c = ref 0 in   (* Counter, in rare cases different from [p] *)
    let l = Netbuffer.length buf in
    while !p < l do
      if eof_seen then raise Ftp_data_protocol_error; (* Trailing garbage *)
      try
	let p_ff = Netbuffer.index_from buf !p '\255' in  (* or Not_found *)
	if p_ff < l - 1 then (
	  (* Case: The byte 0xff is found, and it is not the last byte *)
	  let n = p_ff - !p in
	  if n>0 then
	    out # really_output (Netbuffer.unsafe_buffer buf) !p n;
	  (* Interpret the escape sequence: *)
	  ( match (Netbuffer.sub buf (p_ff+1) 1).[0] with
		'\001' -> out # output_eor();
	      | '\002' -> self # do_close()
	      | '\003' -> out # output_eor(); self # do_close()
	      | '\255' -> out # output_char '\255'
	      | _      -> raise Ftp_data_protocol_error
	  );
	  p := p_ff + 2;
	  c := !p;
	)
	else (
	  (* Case: The byte 0xff is found, but it is the last byte.
	   * Output the data before this byte, then stop.
	   *)
	  let n = p_ff - !p in
	  if n>0 then
	    out # really_output (Netbuffer.unsafe_buffer buf) !p n;
	  p := l;     (* Loop stops... *)
	  c := p_ff;  (* ... but the last byte remains in the buffer *)
	)
      with
	  Not_found ->
	    (* Case: The byte 0xff is not found *)
	    let n = l - !p in
	    if n > 0 then
	      out # really_output (Netbuffer.unsafe_buffer buf) !p n;
	    p := l;
	    c := l;
    done;
    if !c = l then
      Netbuffer.clear buf
    else
      Netbuffer.delete buf 0 !c;
    ondata();

  method private do_close() =
    if not eof_seen then (
      eof_seen <- true; 
      out # close_out(); 
      onclose()    
    )

  method private check_eof() =
    (* EOF on the input descriptor seen. We just accept that, too *)
    if not eof_seen then (
      self # do_close()
    )

  method private commit() =
    (* Additional integrity checks after [close] *)
    if Netbuffer.length buf <> 0 then raise Ftp_data_protocol_error

end ;;


class stream_record_writer
        ?(onclose = fun () -> ()) 
	?(ondata = fun() -> ())
	(ch : in_record_channel) =
  (* An async_in_channel that generates escape sequences for record
   * boundaries in stream mode, as reads from the in_record_channel
   *
   * See stream_record_reader for escaping.
   *)
object(self)
  val mutable buf = Netbuffer.create 4096
  val mutable buf_0xff = None   (* Position of next 0xff *)
  val mutable data = ""         (* Data to insert immediately *)
  val mutable eof = false       (* Set only if buf is already empty *)
  val mutable pos_in = ch # pos_in
  val mutable closed = false

  method input s p l = 
    if eof && data = "" then (
      (* Return EOF condition *)
      ondata();
      raise End_of_file
    );
    let n =
      if data <> "" then (
	(* Fetching from [data] has precedence *)
	let l' = min l (String.length data) in
	String.blit data 0 s p l';
	data <- String.sub data l' (String.length data - l');
	l'
      )
      else (
	(* Get data from [buf] *)
	let m = 
	  match buf_0xff with
	      None -> Netbuffer.length buf
	    | Some n -> n+1 in
	let l' = min m l in
	if l > 0 && l' = 0 then (
	  if buf_0xff = Some (-1) then (
	    (* Just processed the 0xff byte. Insert another 0xff byte *)
	    data <- "\255";
	    self # set_buf_0xff();
	    self # input s p l
	  )
	  else (
	    (* Netbuffer.length buf = 0: Try to refill *)
	    ( try
		ignore(Netbuffer.add_inplace buf ch#input); (* or End_of_file *)
		if buf_0xff = None then
		  self # set_buf_0xff();
	      with
		  End_of_file ->
		    (* This actually means: End of record. Switch to the
		     * next record.
		     *)
		    ( try 
			ch # input_eor();   (* may raise End_of_file again *)
			data <- "\255\001"; (* Code for EOR *)
		      with
			  End_of_file ->
			    data <- "\255\002"; (* Code for EOF *)
			    eof <- true;
		    )
	    );
	    self # input s p l  (* loop *)
	  )
	)
	else (
	  (* Return l' bytes *)
	  Netbuffer.blit buf 0 s p l';
	  Netbuffer.delete buf 0 l';
	  ( match buf_0xff with
		None   -> buf_0xff <- None
	      | Some n -> buf_0xff <- Some (n - l')
	  );
	  l'
	)
      )
    in
    pos_in <- pos_in + n;
    if n > 0 then ondata();
    n

  method private set_buf_0xff() =
    try
      let k = Netbuffer.index_from buf 0 '\255' in
      buf_0xff <- Some k
    with
	Not_found ->
	  buf_0xff <- None


  method close_in () = 
    if not closed then (
      ch # close_in();
      closed <- true;
      onclose()
    )


  method pos_in = pos_in

  method can_input = true

  method request_notification (f : unit -> bool) = ()
    (* No need to implement this method as [can_input] never changes its
     * value
     *)
end ;;



type stream_state =
    [ `Block_start    
	(* The buffer begins with the next block *)
    | `Data of bool * bool * int    
	(* The buffer continues the data block.
	 * Arguments: (eor, eof, remaining bytes) 
	 *)
    | `Restart_marker of bool * bool * int 
	(* The buffer continues the restart marker block.
	 * Arguments: (eor, eof, remaining bytes)
	 *)
    | `Logical_eof    
	(* Logical EOF seen; the buffer should be empty *)
    ]

class block_record_reader
        ?(onclose = fun () -> ()) 
	?(ondata = fun() -> ())
	?(commit = ref (fun () -> ()))
	(out : out_record_channel) =
  (* An async_out_channel that recognizes the block format. Content data
   * are forwarded to the out_record_channel as well as record boundaries.
   *
   * Block format:
   * 1st byte: Descriptor
   *    Bitwise OR of: 
   *      0x80 = EOR after data block
   *      0x40 = EOF after data block
   *      0x20 = Suspected errors in data
   *      0x10 = Data block is restart marker (ignored by this impl.)
   * 2nd, 3rd byte: Length of data block
   * 4th block ...: data block (no escaping)
   *
   * [onclose] is called when the logical EOF is found in the stream.
   *
   * [ondata] is called when [self#output] accepts at least one byte
   *
   * [commit] is initialized to [self#commit].
   *)
  let buf = Netbuffer.create 512 in
  let local_onclose = ref (fun () -> ()) in  (* assigned in initializer *)
  let local_ondata  = ref (fun () -> ()) in
object(self)
  inherit
    in_buffer 
      ~onclose:(fun () -> !local_onclose()) 
      ~ondata:(fun () -> !local_ondata()) 
      ~buf ()

  val mutable state = (`Block_start : stream_state)
  val mutable out_eof = false

  initializer
    local_onclose := self # check_eof;
    local_ondata  := self # forward;
    commit := self # commit;

  method private forward() =
    let s = ref state in
    let p = ref 0 in   (* Position in [buf] *)
    let c = ref 0 in   (* Counter, in rare cases different from [p] *)
    let l = Netbuffer.length buf in
    while !p < l do
      match !s with
	  `Block_start ->
	    if !p + 3 < l then (
	      (* Case: A complete block header is found *)
	      let block_header = Netbuffer.sub buf !p 3 in
	      let descr_byte = Char.code block_header.[0] in
	      let msb_length = Char.code block_header.[1] in
	      let lsb_length = Char.code block_header.[2] in
	      if descr_byte land 0x0f <> 0 then 
		raise Ftp_data_protocol_error;
	        (* Unknown bits are set in the descriptor byte *)
	      let eor = descr_byte land 0x80 <> 0 in
	      let eof = descr_byte land 0x40 <> 0 in
	      let restart = descr_byte land 0x10 <> 0 in
	      let length = msb_length * 256 + lsb_length in
	      s := ( if length = 0 && eof then
		       `Logical_eof
		     else if length = 0 then
		       `Block_start
		     else if restart then
		       `Restart_marker(eor,eof,length)
		     else
		       `Data(eor,eof,length)
		   );
	      p := !p + 3;
	      c := !c + 3;
	      if length = 0 then
		self # output_special eor eof
	    )
	    else (
	      (* Case: The beginning of a block header is found. We cannot
	       * process the header.
	       *)
	      p := l;   (* Exit loop *)
	    )
	| `Data(eor,eof,m) ->
	    (* The data block has [m] following bytes, and is optionally
	     * followed by an [eor] and/or [eof] condition
	     *)
	    let n = min m (l - !p) in
	    if n > 0 then
	      out # really_output (Netbuffer.unsafe_buffer buf) !p n;
	    p := !p + n;
	    c := !c + n;
	    let m' = m - n in
	    s := ( if m' = 0 then
		     (if eof then `Logical_eof else `Block_start)
		   else
		     `Data(eor,eof,m')
		 );
	    if m' = 0 then
	      self # output_special eor eof;

	| `Restart_marker(eor,eof,m) ->
	    (* The marker block has [m] following bytes, and is optionally
	     * followed by an [eor] and/or [eof] condition.
	     * We ignore marker blocks except for the [eor] and [eof]
	     * flags.
	     *)
	    let n = min m (l - !p) in
	    p := !p + n;
	    c := !c + n;
	    let m' = m - n in
	    s := ( if m' = 0 then
		     (if eof then `Logical_eof else `Block_start)
		   else
		     `Restart_marker(eor,eof,m')
		 );
	    if m' = 0 then
	      self # output_special eor eof
	| `Logical_eof ->
	    (* This must not happen: Trailing garbage *)
	    raise Ftp_data_protocol_error
    done;
    state <- !s;
    if !c = l then
      Netbuffer.clear buf
    else
      Netbuffer.delete buf 0 !c;
    ondata();

  method private output_special eor eof =
    if eor then 
      out # output_eor();
    if eof then
      self # do_close();

  method private do_close() =
    if not out_eof then (
      out_eof <- true;
      out # close_out(); 
      onclose()
    )

  method private check_eof() =
    (* EOF on the input descriptor seen. We just accept that, too, provided
     * the block was completely transmitted.
     *)
    self # do_close()

  method private commit() =
    (* Additional integrity checks after [close] *)
    match state with
	`Logical_eof -> 
	  ()
      | `Block_start -> 
	  if Netbuffer.length buf <> 0 then 
	    raise Ftp_data_protocol_error;
	  ()
      | _ ->
	  raise Ftp_data_protocol_error

end ;;


class block_record_writer
        ?(onclose = fun () -> ()) 
	?(ondata = fun() -> ())
	(ch : in_record_channel) =
  (* An async_in_channel that generates block format for the data
   * read from the in_record_channel
   *
   * See block_record_reader for format details.
   *)
object(self)
  val mutable buf = Netbuffer.create 4096
  val mutable data = Bytes.create 0  (* Data to insert immediately *)
  val mutable eof = false       (* Set only if buf is already empty *)
  val mutable pos_in = ch # pos_in
  val mutable closed = false

  method input s p l = 
    if eof && Bytes.length data = 0 then (
      (* Return EOF condition *)
      ondata();
      raise End_of_file
    );
    let n =
      if Bytes.length data > 0 then (
	(* Fetching from [data] has precedence *)
	let l' = min l (Bytes.length data) in
	Bytes.blit data 0 s p l';
	data <- Bytes.sub data l' (Bytes.length data - l');
	l'
      )
      else (
	(* Get data from [buf]: *)
	if l = 0 || Netbuffer.length buf > 0 then (
	  let l' = min l (Netbuffer.length buf) in
	  Netbuffer.blit buf 0 s p l';
	  Netbuffer.delete buf 0 l';
	  l'
	)
	else
	  (* Get data directly from ch: *)
	  try
	    ignore(Netbuffer.add_inplace buf ch#input) (* or End_of_file *);
	    (* Create block header: *)
	    let len = Netbuffer.length buf in
	    let msb = len lsr 8 in
	    let lsb = len land 0xff in
	    data <- Bytes.of_string "\000XX";
	    Bytes.set data 1 (Char.chr msb);
	    Bytes.set data 2 (Char.chr lsb);
	    self # input s p l
	  with
	      End_of_file ->
		(* This may be EOR or EOF. Try to switch to the next record: *)
		( try
		    ch # input_eor();
		    (* It is EOR: *)
		    data <- Bytes.of_string "\128\000\000";
		  with
		    End_of_file ->
		      (* It is EOF! *)
		      eof <- true;
		      data <- Bytes.of_string "\064\000\000";
		);
		self # input s p l
      )
    in
    pos_in <- pos_in + n;
    if n > 0 then ondata();
    n


  method close_in () = 
    if not closed then (
      ch # close_in();
      closed <- true;
      onclose()
    )

  method pos_in = pos_in

  method can_input = true

  method request_notification (f : unit -> bool) = ()
    (* No need to implement this method as [can_input] never changes its
     * value
     *)
end ;;


let transact_e ~src ~dst ~write_eof_dst ~close_src ~close_dst proc_e esys =
  let e = proc_e src dst
    ++ (fun _ ->
          ( if write_eof_dst then
              Uq_io.write_eof_e dst
            else
              (eps_e (`Done false) esys)
          )
          ++
            (fun _ ->
               if close_src then
                 Uq_io.shutdown_e src
               else
                 (eps_e (`Done ()) esys)
            )
          ++ 
            (fun () ->
               if close_dst then
                 Uq_io.shutdown_e dst
               else
                 (eps_e (`Done ()) esys)
            )
       ) in
  e >>
    (function
      | `Done _ -> `Done ()
      | `Error e ->
           if close_src then (try Uq_io.inactivate src with _ -> ());
           if close_dst then (try Uq_io.inactivate dst with _ -> ());
           `Error e
      | `Aborted -> `Aborted
    )
;;


let copy_e src dst =
  Uq_io.copy_e src dst
  >> (function
       | `Done _ -> `Done ()
       | `Error e -> `Error e
       | `Aborted -> `Aborted
     )


let rec unwrap_input_loop_e strbuf buf1 buf2 p esys src dst =
  let s = Bytes.make 4 '\000' in
  Uq_io.really_input_e src (`Bytes s) 0 4
  ++ (fun () ->
        if Bytes.get s 0 <> '\000' then
          raise Ftp_data_protocol_error;
        let n =
          (Char.code (Bytes.get s 1) lsl 16) lor 
            (Char.code (Bytes.get s 2) lsl 8) lor
              Char.code (Bytes.get s 3) in
        if n > Bigarray.Array1.dim buf1 then
          raise Ftp_data_protocol_error;
        Uq_io.really_input_e src (`Memory buf1) 0 n
        ++ 
          (fun () ->
             let buf1_sub = Bigarray.Array1.sub buf1 0 n in
             let n_out = p.ftp_unwrap_m buf1_sub buf2 in
             if n_out=0 then
               eps_e (`Done ()) esys
             else
               let buf2_sub = Bigarray.Array1.sub buf2 0 n_out in
               (* NB. async channels do not support `Memory, so we do this
                  superflous copy here
                *)
               Netsys_mem.blit_memory_to_bytes buf2_sub 0 strbuf 0 n_out;
               Uq_io.really_output_e dst (`String strbuf) 0 n_out
               ++ (fun () ->
                     unwrap_input_loop_e strbuf buf1 buf2 p esys src dst
                  )
            )
     )


let unwrap_input_e p esys src dst =
  let buf1 = Netsys_mem.pool_alloc_memory Netsys_mem.default_pool in
  let buf2 = Netsys_mem.pool_alloc_memory Netsys_mem.default_pool in
  let strbuf = Bytes.create Netsys_mem.default_block_size in
  unwrap_input_loop_e strbuf buf1 buf2 p esys src dst


let rec wrap_output_loop_e strbuf buf1 buf2 limit p esys src dst =
  ( Uq_io.input_e src (`Bytes strbuf) 0 limit
    >> Uq_io.eof_as_none
  )
  ++ (fun n_opt ->
        let n =
          match n_opt with
            | Some n -> n
            | None -> 0 in
        (* NB. async channels do not support `Memory, so we do this
           superflous copy here
         *)
        Netsys_mem.blit_bytes_to_memory strbuf 0 buf1 0 n;
        let buf1_sub = Bigarray.Array1.sub buf1 0 n in
        let n_out = p.ftp_wrap_m buf1_sub buf2 in
        let buf2_sub = Bigarray.Array1.sub buf2 0 n_out in
        let s = Bytes.make 4 '\000' in
        Bytes.set s 1 (Char.chr ((n_out lsr 16) land 0xff));
        Bytes.set s 2 (Char.chr ((n_out lsr 8) land 0xff));
        Bytes.set s 3 (Char.chr (n_out land 0xff));
        Uq_io.really_output_e dst (`Bytes s) 0 4
        ++ (fun () ->
              Uq_io.really_output_e dst (`Memory buf2_sub) 0 n_out
              ++ (fun () ->
                  if n_opt = None then
                    eps_e (`Done ()) esys
                  else
                    wrap_output_loop_e strbuf buf1 buf2 limit p esys src dst
                 )
           )
     )

let wrap_output_e p esys src dst =
  let buf1 = Netsys_mem.pool_alloc_memory Netsys_mem.default_pool in
  let buf2 = Netsys_mem.pool_alloc_memory Netsys_mem.default_pool in
  let strbuf = Bytes.create Netsys_mem.default_block_size in
  let limit = p.ftp_wrap_limit() in
  wrap_output_loop_e strbuf buf1 buf2 limit p esys src dst


let receive_e ~src ~dst ~close_dst esys protector_opt =
  let src = `Multiplex src in
  let dst = `Async_out(dst,esys) in
  let proc_e =
    match protector_opt with
      | None ->
          copy_e
      | Some p ->
          unwrap_input_e p esys in
  transact_e
    ~src ~dst ~write_eof_dst:false ~close_src:false ~close_dst proc_e esys
;;


let tls_receive_e ?resume ~tls_config ~peer_name 
                  ~src ~dst ~close_dst esys =
  let src1 =
    Uq_multiplex.tls_multiplex_controller
      ?resume ~role:`Client ~peer_name tls_config src in
  receive_e ~src:src1 ~dst ~close_dst:false esys None
  ++
    (fun () ->
       (* Shut down the src completely *)
       Uq_io.shutdown_e (`Multiplex src)
       ++ (fun () ->
             if close_dst then
               dst # close_out();
             eps_e (`Done ()) esys
          )
    )
;;


let opt_tls_receive_e ?tls ?protector ~src ~dst ~close_dst esys =
  match tls with
    | None ->
         receive_e
           ~src ~dst ~close_dst esys protector
    | Some(tls_config, peer_name, resume) ->
         tls_receive_e 
           ~tls_config 
           ~peer_name ?resume ~src ~dst ~close_dst esys
;;


let send_e ~src ~dst ~write_eof_dst ~close_src esys protector_opt =
  let src = `Async_in(src,esys) in
  let dst = `Multiplex dst in
  let proc_e =
    match protector_opt with
      | None ->
          copy_e
      | Some p ->
          wrap_output_e p esys in
  transact_e ~src ~dst ~write_eof_dst ~close_src ~close_dst:false proc_e esys
;;


let tls_send_e ?resume ~tls_config ~peer_name 
                  ~src ~dst ~write_eof_dst ~close_src esys =
  let dst =
    Uq_multiplex.tls_multiplex_controller
      ?resume ~role:`Client ~peer_name tls_config dst in
  send_e ~src ~dst ~write_eof_dst ~close_src esys None
;;


let opt_tls_send_e ?tls ?protector ~src ~dst ~write_eof_dst ~close_src esys =
  match tls with
    | None ->
         send_e
           ~src ~dst ~write_eof_dst ~close_src esys protector
    | Some(tls_config, peer_name, resume) ->
         tls_send_e 
           ~tls_config
           ~peer_name ?resume ~src ~dst ~write_eof_dst ~close_src esys
;;
	

class ftp_data_receiver_impl 
        ?tls ?protector
        ~esys 
	~(mode : transmission_mode)
	~(local_receiver : local_receiver)
	~descr
        ~timeout
        ~timeout_exn () =
  (* This is almost the same as the class [ftp_data_receiver] (which is
   * explained in the mli). This engine, however, uses the state [`Aborted]
   * to signal that it stops processing, e.g. because the logical EOF
   * marker has been found.
   *)
  (* onclose: transition to `Down or `Clean; abort engine
   * ondata: transition to `Transfer_in_progress
   *)
  let onclose_ref = ref (fun () -> ()) in  (* Later assigned *)
  let ondata_ref  = ref (fun () -> ()) in
  let onclose()   = !onclose_ref () in
  let ondata()    = !ondata_ref () in
  let commit      = ref (fun () -> ()) in  (* Assigned in *_reader *)
  (* The [commit] function is actually a private method of one of the
   * *_reader classes. It is called to signal that the data transfer
   * has been successful, and that the message should be checked for
   * integrity. [commit] should raise an exception if these checks fail.
   *)
  let dst =
    match mode with
	`Stream_mode ->
	  ( match local_receiver with
		`File_structure ch ->
		  new stream_file_reader ~onclose ~ondata (*~commit*) ch
	      | `Record_structure ch ->
		  new stream_record_reader ~onclose ~ondata ~commit ch
	  )
      | `Block_mode ->
	  let rec_ch =
	    match local_receiver with
		`File_structure ch ->
		  new fake_out_record_channel ch
	      | `Record_structure ch -> 
		  ch in
	  new block_record_reader ~onclose ~ondata ~commit rec_ch
  in
  let src = 
    Uq_multiplex.create_multiplex_controller_for_connected_socket
      ~close_inactive_descr:false
      ~timeout:(timeout,timeout_exn)
      descr esys in
object (self)
(*
  inherit Uq_transfer.receiver 
    ~src:descr ~dst ~close_src:false ~close_dst:true esys
 *)
  inherit [unit] Uq_engines.delegate_engine
            (opt_tls_receive_e
               ?tls ?protector ~src ~dst ~close_dst:true esys)

  val mutable descr_state = (`Transfer_in_progress : descr_state)

  initializer
    onclose_ref := self#close;

  method local_receiver = local_receiver

  method descr = descr

  method descr_state = descr_state

  method commit() = !commit()

  method private close() =
    let g = Unixqueue.new_group esys in
    Unixqueue.once esys g 0.0 self#abort;
    descr_state <- `Down;
    (* We could also go back to `Clean for some data protocols. However,
       I doubt that would work well with all the buggy ftp servers
     *)
    try
      Unix.shutdown descr Unix.SHUTDOWN_ALL
    with _ -> ()

end ;;


class ftp_data_receiver ?tls ?protector ~esys ~mode ~local_receiver ~descr
                        ~timeout ~timeout_exn () =
  (* The engine [e] may go into the state [`Aborted] when it finishes
   * normally. This is wrong; the engine should go to [`Done ()] instead,
   * and [`Aborted] is reserved for the case when the user of the class
   * calls [abort]. We correct this here by mapping the state.
   *)
  let () =
    if tls <> None && protector <> None then
      failwith "Netftp_data_endpoint.ftp_data_receiver: Only one security layer \
                can be enabled" in
  let e = 
    new ftp_data_receiver_impl
          ?tls ?protector ~esys ~mode ~local_receiver ~descr ~timeout
          ~timeout_exn () in
  let commit() =
    try e#commit(); `Done()
    with
	error -> `Error error
  in
object(self)
  inherit 
    [unit,unit]
    map_engine
      ~map_done:(fun _ -> commit())
      ~map_aborted:(fun () ->
		      match e # descr_state with
			  (`Clean | `Down) -> commit()
			| _ -> `Aborted)
      (e :> unit engine)

  method local_receiver = e # local_receiver

  method descr = e # descr

  method descr_state = e # descr_state

  method abort() =
    try e#abort() with _ -> ()

  (* method e = e *)

end ;;


class ftp_data_sender
        ?tls ?protector
        ~esys 
	~(mode : transmission_mode)
	~(local_sender : local_sender)
	~descr
        ~timeout
        ~timeout_exn
        () =
  let () =
    if tls <> None && protector <> None then
      failwith "Netftp_data_endpoint.ftp_data_sender: Only one security layer \
                can be enabled" in
  let descr_state = ref (`Transfer_in_progress : descr_state) in
  let src =
    match mode with
	`Stream_mode ->
	  ( match local_sender with
		`File_structure ch ->
		  new stream_file_writer ch
	      | `Record_structure ch ->
		  new stream_record_writer ch
	  )
      | `Block_mode ->
	  let rec_ch =
	    match local_sender with
		`File_structure ch ->
		  new fake_in_record_channel ch
	      | `Record_structure ch -> 
		  ch in
	  new block_record_writer rec_ch
  in
  let dst = 
    Uq_multiplex.create_multiplex_controller_for_connected_socket
      ~close_inactive_descr:false
      ~timeout:(timeout,timeout_exn)
      descr esys in
  let e1 = 
    opt_tls_send_e
      ?tls ?protector ~src ~dst
      ~write_eof_dst:true ~close_src:true esys in
  let e2 =
    e1 ++
      (fun () ->
         descr_state := `Down;
         (* We could also go back to `Clean for some data protocols. However,
            I doubt that would work well with all the buggy ftp servers
          *)
         ( try
             Unix.shutdown descr Unix.SHUTDOWN_ALL
           with _ -> ()
         );
         eps_e (`Done ()) esys
      ) in  
object (self)
(*
  inherit Uq_transfer.sender
    ~src ~dst:descr ~close_src:true ~close_dst:false esys
 *)
  inherit [unit] Uq_engines.delegate_engine e2

  method local_sender = local_sender
  method descr = descr
  method descr_state = !descr_state
end ;;


class type ftp_data_engine =
object
  inherit [unit] Uq_engines.engine
  method descr : Unix.file_descr
  method descr_state : descr_state
end    


let () =
  Netsys_signal.init()

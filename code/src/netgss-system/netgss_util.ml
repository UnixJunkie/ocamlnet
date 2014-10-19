(* $Id$ *)

(* Utilities for the generated object encapsulation *)

open Netsys_gssapi
open Netgss_bindings

let identity x = x

let _OM_uint32_of_int32 = identity
let _int32_of_OM_uint32 = identity

let calling_errors =
  [| `None;
     `Inaccessible_read;
     `Inaccessible_write;
     `Bad_structure
    |]


let routine_errors =
  [| `None;
     `Bad_mech;
     `Bad_name;
     `Bad_nametype;
     `Bad_bindings;
     `Bad_status;
     `Bad_mic;
     `No_cred;
     `No_context;
     `Defective_token;
     `Defective_credential;
     `Credentials_expired;
     `Context_expired;
     `Failure;
     `Bad_QOP;
     `Unauthorized;
     `Unavailable;
     `Duplicate_element;
     `Name_not_mn;
    |]

let suppl_status_flags =
  [| `Continue_needed;
     `Duplicate_token;
     `Old_token;
     `Unseq_token;
     `Gap_token;
    |]

let decode_status n : major_status =
  let bits_calling_error =
    Int32.to_int(Int32.shift_right_logical n 24) in
  let bits_routine_error =
    Int32.to_int(Int32.logand (Int32.shift_right_logical n 16) 0xffl) in
  let bits_suppl_info =
    Int32.to_int(Int32.logand n 0xffffl) in
  try
    if bits_calling_error >= Array.length calling_errors then raise Not_found;
    if bits_routine_error >= Array.length routine_errors then raise Not_found;
    let suppl_info, _ =
      Array.fold_right
        (fun flag (l, k) ->
           let is_set = (1 lsl k) land bits_suppl_info <> 0 in
           if is_set then
             (flag :: l, k+1)
           else
             (l, k+1)
        )
        suppl_status_flags
        ([], 0) in
    (calling_errors.(bits_calling_error),
     routine_errors.(bits_routine_error),
     suppl_info
    )
  with
    | Not_found ->
         failwith "Netgss.decode_status"

let _gss_ctx_id_t_of_context_option =
  function
  | None -> no_context()
  | Some ctx -> ctx

let _context_option_of_gss_ctx_id_t ctx =
  if is_no_context ctx then
    None
  else
    Some ctx

let _gss_buffer_t_of_token s =
  buffer_of_string s 0 (String.length s)

let _gss_buffer_t_of_token_option =
  function
  | Some s ->
       buffer_of_string s 0 (String.length s)
  | None ->
       buffer_of_string "" 0 0   (* should be ok for GSS_C_NO_BUFFER *)


let _token_of_gss_buffer_t buf =
  string_of_buffer buf

let _gss_buffer_t_of_message (ml : Xdr_mstring.mstring list) =
  match ml with
    | [] ->
         buffer_of_string "" 0 0
    | [ m ] ->
         ( match m#preferred with
             | `Memory ->
                  (* No copy in this case *)
                  let (mem1, pos) = m#as_memory in
                  let mem2 = Bigarray.Array1.sub mem1 pos m#length in
                  buffer_of_memory mem2
             | `String ->
                  let (str, pos) = m#as_string in
                  buffer_of_string str pos m#length
         )
    | _ ->
         let len = Xdr_mstring.length_mstrings ml in
         let mem = Bigarray.Array1.create Bigarray.char Bigarray.c_layout len in
         Xdr_mstring.blit_mstrings_to_memory ml mem;
         buffer_of_memory mem

                                             
let _message_of_gss_buffer_t pref_type buf =
  match pref_type with
    | `Memory ->
         let mem = memory_of_buffer buf in
         [ Xdr_mstring.memory_to_mstring mem ]
         (* CHECK: no copy here. These buffers are "use once" buffers *)
    | `String ->
         let str = string_of_buffer buf in
         [ Xdr_mstring.string_to_mstring str ]

let _gss_channel_bindings_t_of_cb_option _ =
  (* FIXME *)
  no_channel_bindings()

let _oid_of_gss_OID gss_oid =
  try
    let der = der_of_oid gss_oid in
    let p = ref 0 in
    Netgssapi_support.der_value_to_oid der p (String.length der)
  with Not_found -> [| |]

let _gss_OID_of_oid oid =
  if oid = [| |] then
    no_oid()
  else
    let der = Netgssapi_support.oid_to_der_value oid in
    oid_of_der der

let _oid_set_of_gss_OID_set gss_set =
  try
    let gss_oid_a = array_of_oid_set gss_set in
    let oid_a = Array.map _oid_of_gss_OID gss_oid_a in
    Array.to_list oid_a
  with Not_found -> []

let _gss_OID_set_of_oid_set set =
  let set_a = Array.of_list set in
  let gss_oid_a = Array.map _gss_OID_of_oid set_a in
  oid_set_of_array gss_oid_a

let _time_of_OM_uint32 n =
  if n = gss_indefinite() then
    `Indefinite
  else
    (* be careful with negative values. In C, the numbers are unsigned *)
    if n >= 0l then
      `This (Int32.to_float n)
    else
      let offset = (-2.0) *. Int32.to_float Int32.min_int in
      `This (Int32.to_float n +. offset)

let uint32_of_float t =
  if t >= Int32.to_float Int32.max_int +. 1.0 then
    let offset = (-2.0) *. Int32.to_float Int32.min_int in
    let t1 = t -. offset in
    let t2 = min t1 (Int32.to_float Int32.max_int) in
    Int32.of_float t2
  else
    Int32.of_float(max t 0.0)
                  

let _OM_uint32_of_time =
  function
  | `Indefinite -> gss_indefinite()
  | `This t -> uint32_of_float t

let _OM_uint32_of_time_opt =
  function
  | None -> 0l
  | Some t -> uint32_of_float t


let _OM_uint32_of_wrap_size n =
  if n < 0 || Int64.of_int n > Int64.of_int32 Int32.max_int then
    failwith "Netgss: wrap size out of range";
  Int32.of_int n

let _wrap_size_of_OM_uint32 n =
  (* the output is normally smaller than the input *)
  if n < 0l || Int64.of_int32 n > Int64.of_int max_int then
    failwith "Netgss: wrap size out of range";
  Int32.to_int n


let _flags_of_req_flags flags = (flags : Netsys_gssapi.req_flag list :> flags)

let gss_display_minor_status min_status mech_type =
  let out_major = ref 0l in
  let out_minor = ref 0l in
  let l = ref [] in
  let mctx = ref 0l in
  let cont = ref true in
  while !cont do
    let (major, minor, new_mctx, display_string) =
      Netgss_bindings.gss_display_status
        min_status `Mech_code mech_type !mctx in
    out_major := major;
    out_minor := minor;
    mctx := new_mctx;
    let success = Int32.logand major 0xffff0000l = 0l in
    if success then
      l := display_string :: !l;
    cont := !mctx <> 0l && success;
  done;
  let strings =
    List.map string_of_buffer (List.rev !l) in
  (!out_major, !out_minor, strings)
#directory "+compiler-libs"
(* only for Btype.hash_variant *)

#load "str.cma"
#load "ocamlcommon.cma"

open Printf

let p1_re = Str.regexp "^\\(.*\\)(\\(.*\\))"
let p2_re = Str.regexp "[ \t]*,[ \t]*"
let p3_re = Str.regexp "[ \t]+"

let parse decl =
  try
    if Str.string_match p1_re decl 0 then (
      let part1 = Str.matched_group 1 decl in
      let part2 = Str.matched_group 2 decl in
      let result_name = Str.split p3_re part1 in
      let params =
        List.map
          (fun param_s ->
             let l = Str.split p3_re param_s in
             let n = List.hd (List.rev l) in
             let ty = List.rev (List.tl (List.rev l)) in
             (n, String.concat " " ty)
          )
          (Str.split p2_re part2) in
      let name = List.hd (List.rev result_name) in
      let result = List.rev (List.tl (List.rev result_name)) in
      (name, String.concat " " result, params)
    )
    else raise Not_found
  with
    | Not_found ->
         failwith ("Parse error: " ^ decl)


let has_prefix ~prefix s =
  let l1 = String.length s in
  let l2 = String.length prefix in
  l2 <= l1 && String.sub s 0 l2 = prefix


type abs_ptr =
    { abs_free_fn : string }

let abstract_ptr abs_free_fn =
  `Abstract_ptr { abs_free_fn }

(**********************************************************************)
(* Abstract_enum                                                      *)
(**********************************************************************)

let gen_abstract_enum c mli ml tyname =
  fprintf mli "type %s\n" tyname;
  fprintf ml "type %s\n" tyname;

  fprintf c "/************** %s *************/\n\n" tyname;
  fprintf c "struct enumstruct_%s { %s value; long oid; };\n\n" tyname tyname;
  fprintf c "#define enumstructptr_%s_val(v) \
             ((struct enumstruct_%s *) (Data_custom_val(v)))\n" tyname tyname;
  fprintf c "#define enum_%s_unwrap(v) \
             (enumstructptr_%s_val(v)->value)\n" tyname tyname;
  fprintf c "long enum_%s_oid = 0;\n" tyname;

  fprintf c "\n";
  fprintf c "static int enum_%s_compare(value v1, value v2) {\n" tyname;
  fprintf c "  struct enumstruct_%s *p1;\n" tyname;
  fprintf c "  struct enumstruct_%s *p2;\n" tyname;
  fprintf c "  p1 = enumstructptr_%s_val(v1);\n" tyname;
  fprintf c "  p2 = enumstructptr_%s_val(v2);\n" tyname;
  fprintf c "  return p1->oid - p2->oid;\n";
  fprintf c "}\n\n";

  fprintf c "static struct custom_operations enum_%s_ops = {\n" tyname;
  fprintf c "  \"\",\n";
  fprintf c "  custom_finalize_default,\n";
  fprintf c "  enum_%s_compare,\n" tyname;
  fprintf c "  custom_hash_default,\n";
  fprintf c "  custom_serialize_default,\n";
  fprintf c "  custom_deserialize_default\n";
  fprintf c "};\n\n";

  fprintf c "static %s unwrap_%s(value v) {\n" tyname tyname;
  fprintf c "  return enum_%s_unwrap(v);\n" tyname;
  fprintf c "}\n\n";

  fprintf c "static value wrap_%s(%s x) {\n" tyname tyname;
  fprintf c "  value v;\n";
  fprintf c "  v = caml_alloc_custom(&enum_%s_ops, \
                                     sizeof(struct enumstruct_%s), 0, 1);\n"
         tyname tyname;
  fprintf c "  enumstructptr_%s_val(v)->value = x;\n" tyname;
  fprintf c "  enumstructptr_%s_val(v)->oid = enum_%s_oid++;\n" tyname tyname;
  fprintf c "  return v;\n";
  fprintf c "}\n\n";

  ()

(**********************************************************************)
(* Abstract_ptr                                                       *)
(**********************************************************************)

let gen_abstract_ptr c mli ml tyname abs =
  fprintf mli "type %s\n" tyname;
  fprintf ml "type %s\n" tyname;

  fprintf c "/************** %s *************/\n\n" tyname;
  fprintf c "struct absstruct_%s { %s value; long oid; };\n\n" tyname tyname;
  fprintf c "#define absstructptr_%s_val(v) \
             ((struct absstruct_%s *) (Data_custom_val(v)))\n" tyname tyname;
  fprintf c "#define abs_%s_unwrap(v) \
             (absstructptr_%s_val(v)->value)\n" tyname tyname;
  fprintf c "long abs_%s_oid = 0;\n" tyname;

  fprintf c "\n";
  fprintf c "static int abs_%s_compare(value v1, value v2) {\n" tyname;
  fprintf c "  struct absstruct_%s *p1;\n" tyname;
  fprintf c "  struct absstruct_%s *p2;\n" tyname;
  fprintf c "  p1 = absstructptr_%s_val(v1);\n" tyname;
  fprintf c "  p2 = absstructptr_%s_val(v2);\n" tyname;
  fprintf c "  return p1->oid - p2->oid;\n";
  fprintf c "}\n\n";

  fprintf c "static void abs_%s_finalize(value v1) {\n" tyname;
  fprintf c "  struct absstruct_%s *p1;\n" tyname;
  fprintf c "  p1 = absstructptr_%s_val(v1);\n" tyname;
  fprintf c "  %s(p1->value);\n" abs.abs_free_fn;
  fprintf c "}\n\n";

  fprintf c "static struct custom_operations abs_%s_ops = {\n" tyname;
  fprintf c "  \"\",\n";
  fprintf c "  abs_%s_finalize,\n" tyname;
  fprintf c "  abs_%s_compare,\n" tyname;
  fprintf c "  custom_hash_default,\n";
  fprintf c "  custom_serialize_default,\n";
  fprintf c "  custom_deserialize_default\n";
  fprintf c "};\n\n";

  fprintf c "static %s unwrap_%s(value v) {\n" tyname tyname;
  fprintf c "  return abs_%s_unwrap(v);\n" tyname;
  fprintf c "}\n\n";

  fprintf c "static value wrap_%s(%s x) {\n" tyname tyname;
  fprintf c "  value v;\n";
  fprintf c "  if (x == NULL) failwith(\"wrap_%s: NULL pointer\");\n" tyname;
  fprintf c "  v = caml_alloc_custom(&abs_%s_ops, \
                                     sizeof(struct absstruct_%s), 0, 1);\n"
         tyname tyname;
  fprintf c "  absstructptr_%s_val(v)->value = x;\n" tyname;
  fprintf c "  absstructptr_%s_val(v)->oid = abs_%s_oid++;\n" tyname tyname;
  fprintf c "  return v;\n";
  fprintf c "}\n\n";

  ()

(**********************************************************************)
(* Enum                                                               *)
(**********************************************************************)

let vert_re = Str.regexp "[|]"

let c_name_of_enum n =
  Str.replace_first vert_re "" n

let ml_name_of_enum n =
  try
    let l = String.length n in
    let p = String.index n '|' in
    String.capitalize (String.lowercase (String.sub n (p+1) (l-p-1)))
  with
    | Not_found ->
         String.capitalize (String.lowercase n)


let gen_enum c mli ml tyname cases =
  List.iter
    (fun f ->
       fprintf f "type %s =\n" tyname;
       fprintf f "  [ ";
       let first = ref true in
       List.iter
         (fun case ->
            if not !first then fprintf f "  | ";
            first := false;
            fprintf f "`%s\n" (ml_name_of_enum case)
         )
         cases;
       fprintf f "  ]\n";
    )
    [ mli; ml ];

  fprintf c "/************** %s *************/\n\n" tyname;
  fprintf c "static value wrap_%s(%s x) {\n" tyname tyname;
  fprintf c "  switch (x) {\n";
  List.iter
    (fun case ->
       let n1 = c_name_of_enum case in
       let n2 = ml_name_of_enum case in
       let h = Btype.hash_variant n2 in
       fprintf c "    case %s: return Val_long(%d);\n"
               n1 h;
    )
    cases;
  fprintf c "  };\n";
  fprintf c "  failwith(\"wrap_%s: unexpected value\");\n" tyname;
  fprintf c "}\n\n";

  fprintf c "static %s unwrap_%s(value v) {\n" tyname tyname;
  fprintf c "  switch (Long_val(v)) {\n";
  List.iter
    (fun case ->
       let n1 = c_name_of_enum case in
       let n2 = ml_name_of_enum case in
       let h = Btype.hash_variant n2 in
       fprintf c "    case %d: return %s;\n"
               h n1;
    )
    cases;
  fprintf c "  };\n";
  fprintf c "  failwith(\"unwrap_%s: unexpected value\");\n" tyname;
  fprintf c "}\n\n";

  ()

(**********************************************************************)
(* Flags                                                              *)
(**********************************************************************)

let gen_flags c mli ml tyname cases =
  List.iter
    (fun f ->
       fprintf f "type %s_flag =\n" tyname;
       fprintf f "  [ ";
       let first = ref true in
       List.iter
         (fun case ->
            if not !first then fprintf f "  | ";
            first := false;
            fprintf f "`%s\n" (ml_name_of_enum case)
         )
         cases;
       fprintf f "  ]\n";
       fprintf f "type %s = %s_flag list\n" tyname tyname;
    )
    [ mli; ml ];

  fprintf c "/************** %s *************/\n\n" tyname;
  fprintf c "static value wrap_%s(%s x) {\n" tyname tyname;
  fprintf c "  CAMLparam0();\n";
  fprintf c "  CAMLlocal2(v,u);\n";
  fprintf c "  v = Val_long(0);\n";
  List.iter
    (fun case ->
       let n1 = c_name_of_enum case in
       let n2 = ml_name_of_enum case in
       let h = Btype.hash_variant n2 in
       fprintf c "  if (x & %s) {\n" n1;
       fprintf c "    u = caml_alloc(2,0);\n";
       fprintf c "    Field(u, 0) = Val_long(%d);\n" h;
       fprintf c "    Field(u, 1) = v;\n";
       fprintf c "    v = u;\n";
       fprintf c "  };\n";
    )
    cases;
  fprintf c "  CAMLreturn(v);\n";
  fprintf c "}\n\n";

  fprintf c "static %s unwrap_%s(value v) {\n" tyname tyname;
  fprintf c "  %s x = 0;\n" tyname;
  fprintf c "  while (Is_block(v)) {\n";
  fprintf c "    switch (Long_val(Field(v,0))) {\n";
  List.iter
    (fun case ->
       let n1 = c_name_of_enum case in
       let n2 = ml_name_of_enum case in
       let h = Btype.hash_variant n2 in
       fprintf c "      case %d: x |= %s; break;\n"
               h n1;
    )
    cases;
  fprintf c "    };\n";
  fprintf c "    v = Field(v,1);\n";
  fprintf c "  };\n";
  fprintf c "  return x;\n";
  fprintf c "}\n\n";

  ()

(**********************************************************************)
(* Same_as                                                            *)
(**********************************************************************)

let gen_same_as c mli ml old_tyname tyname =
  fprintf mli "type %s = %s\n" tyname old_tyname;
  fprintf ml "type %s = %s\n" tyname old_tyname;
  fprintf c "#define wrap_%s wrap_%s\n" tyname old_tyname;
  fprintf c "#define unwrap_%s wrap_%s\n" tyname old_tyname

(**********************************************************************)
(* Functions                                                          *)
(**********************************************************************)

let ws_re = Str.regexp "[ \t]+"

let split_type ty =
  let l = Str.split ws_re ty in
  match l with
    | "const" :: l' -> true, l'
    | _ -> false, l


let rec translate_type_to_ml name ty =
  let (is_const, ty_list) = split_type ty in
  match ty_list with
    | [ "void" ] -> "unit"
    | [ "int" ] -> "int"
    | [ "uint" ] -> "int"
    | [ "bool" ] -> "bool"
    | [ "double" ] -> "float"
    | [ "ztstr" ] -> "string"
    | [ elt; "ztlist" ] -> translate_type_to_ml name elt ^ " list"
    | [ elt; "array" ] -> translate_type_to_ml name elt ^ " array"
    | [ "array_size" ] -> "int"
    | [ id; "bigarray" ] -> "Netsys_mem.memory"
    | [ id; "bigarray_size" ] -> "int"
    | [ "bigarray_datum" ] -> "Netsys_mem.memory"
    | [ "str_datum" ] -> "string"
    | [ "file_descr" ] -> "Unix.file_descr"
    | [ tyname ] -> 
         ( try
             let p = String.index tyname '/' in
             let tyname2 =
               String.sub tyname (p+1) (String.length tyname -p - 1) in
             translate_type_to_ml name tyname2
           with Not_found ->
                tyname
         )
    | _ -> failwith ("Bad type in function " ^ name ^ ": " ^ ty)


let rec translate_type_to_c name ty =
  let (is_const, ty_list) = split_type ty in
  let c_ty, tag =
    match ty_list with
      | [ "void" ] -> 
           "void", `Ignore
      | [ "int" ] -> 
           "int", `Plain("Int_val", "Val_int")
      | [ "uint" ] -> 
           "unsigned int", `Plain("uint_val", "Val_int")
      | [ "bool" ] -> 
           "int", `Plain("Bool_val", "Val_bool")
      | [ "double" ] -> 
           "double", `Plain("Double_val", "caml_copy_double")
      | [ "ztstr" ] -> 
           "char *", `Plain("String_val", "protected_copy_string")
      | [ "file_descr" ] ->    (* FIXME: win32 *)
           "int", `Plain("Int_val", "Val_int")
      | [ elt; "ztlist" ] -> 
           let el_cty, el_tag = 
             translate_type_to_c name elt in
           el_cty ^ " *", `ZTList el_tag
      | [ elt; "array" ] ->
           let el_cty, el_tag =
             translate_type_to_c name elt in
           el_cty ^ " *", `Array(el_cty, el_tag)
      | [ "array_size" ] ->
           "unsigned int", `Array_size
      | [ id; "bigarray" ] -> 
           "void *", `Bigarray id
      | [ id; "bigarray_size" ] -> 
           "size_t", `Bigarray_size id
(*
      | [ "bigarray_datum" ] -> 
           "gnutls_datum_t", `Bigarray_datum
      | [ "bigarray_datum_p" ] -> 
           "gnutls_datum_t *", `Bigarray_datum
 *)
      | [ tyname ] -> 
           ( try
               let p = String.index tyname '/' in
               let tyname1 =
                 String.sub tyname 0 p in
               let tyname2 =
                 String.sub tyname (p+1) (String.length tyname - p - 1) in
               let (_, tag) = translate_type_to_c name tyname2 in
               (tyname1, tag)
             with Not_found ->
               tyname, `Plain("unwrap_" ^ tyname, "wrap_" ^ tyname)
           )
      | _ -> 
           ty, `Unsupported in
  let c_ty1 =
    if is_const then "const " ^ c_ty else c_ty in
  (c_ty1, tag)


let is_size ty =
  let (is_const, ty_list) = split_type ty in
  match ty_list with
    | [ id; "bigarray_size" ] -> true
    | [ "array_size" ] -> true
    | _ -> false



let rec first n l =
  if n=0 then
    []
  else
    match l with
      | x :: l' -> x :: first (n-1) l'
      | [] -> []


let rec after_first n l =
  if n=0 then
    l
  else
    match l with
      | x :: l' -> after_first (n-1) l'
      | [] -> []


let result_re = Str.regexp "RESULT"

let gen_fun c mli ml name args directives free =
  let input_args =
    List.filter
      (fun (n,kind,ty) -> kind = `In || kind = `In_ignore || kind = `In_out)
      args in
  let input_ml_args0 =
    List.filter
      (fun (n,kind,ty) ->
         kind = `In_out || (kind = `In && not(is_size ty))
      )
      input_args in
  let input_ml_args =
    if input_ml_args0 = [] then [ "dummy", `In, "void" ] else input_ml_args0 in
  let output_args =
    List.filter
      (fun (n,kind,ty) -> kind = `Out || kind = `Out_ignore || kind = `In_out)
      args in
  let output_ml_args0 =
    List.filter
      (fun (n,kind,ty) -> kind = `Out || kind = `In_out)
      output_args in
  let return_args =
    List.filter
      (fun (n,kind,ty) -> kind = `Return || kind = `Return_ignore)
      args in
  let return_arg =
    match return_args with
      | [] -> ("", `Return_ignore, "void")
      | [ return_arg ] -> return_arg
      | _ -> failwith ("More than one return value: " ^ name) in
  let ignore_return_arg =
    let (_, kind, _) = return_arg in
    kind = `Return_ignore in  
  let output_ml_args =
    if ignore_return_arg then (
      if output_ml_args0 = [] then
        ["", `Out_ignore, "void" ]
      else
        output_ml_args0
    )
    else
      return_arg :: output_ml_args0 in
  let trans_input_ml_args =
    List.map
      (fun (_,_,ty) -> translate_type_to_ml name ty)
      input_ml_args in
  let trans_output_ml_args =
    List.map
      (fun (_,_,ty) -> translate_type_to_ml name ty)
      output_ml_args in
  fprintf mli "val %s : %s -> %s\n" 
          name
          (String.concat " -> " trans_input_ml_args)
          (String.concat " * " trans_output_ml_args);
  fprintf ml "external %s : %s -> %s\n" 
          name
          (String.concat " -> " trans_input_ml_args)
          (String.concat " * " trans_output_ml_args);
  fprintf ml " = %S %S\n"
          (if List.length trans_input_ml_args > 5 then
             ("net_" ^ name ^ "__byte")
           else
             ("net_" ^ name)
          )
          ("net_" ^ name);

  let c_args =
    List.map
      (fun (n,kind,ty) ->
         let (c_ty, tag) = translate_type_to_c name ty in
         (n, kind, ty, c_ty, tag)
      )
      args in

  let c_decls = ref [] in
  let ml_locals = ref [] in
  let c_code_pre = ref [] in
  let c_code_post = ref [] in
  let c_code_post_prio = ref [] in
  let c_act_args = ref [] in
  let c_act_ret = ref None in

  let n = ref 0 in
  let new_local() = let k = !n in incr n; sprintf "local_%d" k in

(*
  if not ignore_return_arg then (
    let (n,_,_) = return_arg in
    ml_locals := n :: !ml_locals
  );
 *)

  let n_return = ref 0 in
  let return_names = ref [] in

  List.iter
    (fun (n, kind, ty, c_ty, tag) ->
       if kind <> `Return_ignore || ty <> "void" then (
         let n1 = sprintf "%s__c" n in
         c_decls := sprintf "%s %s;" c_ty n1 :: !c_decls;
         
         if kind = `In || kind = `In_out then (
           match tag with
             | `Plain(to_c,to_ml) ->
                  let need_free = List.mem c_ty free in
                  let unwrap = 
                    sprintf "%s = %s(%s);" n1 to_c n in
                  c_code_pre := unwrap :: !c_code_pre;
                  if need_free then (
                    let free_call =
                      sprintf "free_%s(%s);" c_ty n1 in
                    c_code_post_prio := free_call :: !c_code_post_prio
                  )
             | `Array(el_c_ty, `Plain(to_c,to_ml)) ->
                  let i1 = new_local() in
                  c_decls := sprintf "long %s;" i1 :: !c_decls;
                  let code1 =
                    [ sprintf "%s = (%s) stat_alloc(Wosize_val(%s)*sizeof(%s));" 
                              n1 c_ty n el_c_ty;
                      sprintf "for (%s=0; %s < Wosize_val(%s); %s++) {"
                              i1 i1 n i1;
                      sprintf "  %s[%s] = %s(Field(%s,%s));" n1 i1 to_c n i1;
                      sprintf "};";
                    ] in
                  c_code_pre := List.rev code1 @ !c_code_pre;
                  let el_need_free = List.mem el_c_ty free in
                  let code2 =
                    (if el_need_free then
                       [ sprintf "for (%s=0; %s < Wosize_val(%s); %s++) {"
                                 i1 i1 n i1;
                         sprintf "  free_%s(%s[%s]);" el_c_ty n1 i1;
                         sprintf "};"
                       ]
                     else []) @
                      [ sprintf "stat_free(%s);" n1 ] in
                  c_code_post_prio := List.rev code2 @ !c_code_post_prio;
             | `Array_size ->
                  let (n_array,_,_,_,_) =
                    try
                      List.find
                        (fun (_,_,_,_,tag) -> 
                           match tag with `Array _ -> true | _ -> false
                        )
                        c_args
                    with
                      | Not_found ->
                           failwith ("array_size needs array, fn: " ^  name) in
                  let code =
                    sprintf "%s = (unsigned long) Wosize_val(%s);" n1 n_array in
                  c_code_pre := code :: !c_code_pre
             | `Bigarray id ->
                  let code1 =
                    [ sprintf "%s = Caml_ba_data_val(%s);" n1 n ] in
                  c_code_pre := List.rev code1 @ !c_code_pre;
             | `Bigarray_size id ->
                  let (n_array,_,_,_,_) =
                    try
                      List.find
                        (fun (_,_,_,_,tag) -> 
                           tag = `Bigarray id
                        )
                        c_args
                    with
                      | Not_found ->
                           failwith ("bigarray_size needs bigarray, fn: " ^ 
                                       name) in
                  let code1 =
                    [ sprintf "%s = caml_ba_byte_size(Caml_ba_array_val(%s));"
                              n1 n_array ] in
                  c_code_pre := List.rev code1 @ !c_code_pre;
                  
             | _ ->
                  failwith ("Unsupported arg: " ^ n ^ ", fn " ^ name)
         );

         if kind = `Out || kind = `Return then (
           ml_locals := n :: !ml_locals;
         );

         if kind = `Out || kind = `In_out || kind = `Return then (
           incr n_return;
           return_names := n :: !return_names;
           match tag with
             | `Plain(to_c,to_ml) ->
                  let wrap = 
                    sprintf "%s = %s(%s);" n to_ml n1 in
                  c_code_post := wrap :: !c_code_post
             | `ZTList(`Plain(to_c,to_ml)) ->
                  let i1 = new_local() in
                  let h1 = new_local() in
                  c_decls := sprintf "long %s;" i1 :: !c_decls;
                  ml_locals := h1 :: !ml_locals;
                  let code =
                    [ sprintf "%s = 0;" i1;
                      sprintf "while (%s[%s] != 0) %s++;" n1 i1 i1;
                      sprintf "%s = Val_int(0);" n;
                      sprintf "while (%s > 0) {" i1;
                      sprintf "  %s--;" i1;
                      sprintf "  %s = caml_alloc(2,0);" h1;
                      sprintf "  Field(%s,0) = %s(%s[%s]);" h1 to_ml n1 i1;
                      sprintf "  Field(%s,1) = %s;" h1 n;
                      sprintf "  %s = %s;" n h1;
                      sprintf "};"
                    ] in
                  c_code_post := List.rev code @ !c_code_post;
             | `Array(el_c_ty, `Plain(to_c,to_ml)) ->
                  let (n_size,_,_,_,_) =
                    try
                      List.find
                        (fun (_,_,_,_,tag) -> 
                           tag = `Array_size
                        )
                        c_args
                    with
                      | Not_found ->
                           failwith ("array needs array_size, fn: " ^  name) in
                  let i1 = new_local() in
                  c_decls := sprintf "long %s;" i1 :: !c_decls;
                  let code =
                    [ sprintf "if (%s == NULL) failwith(\"%s: NULL pointer\");"
                              n1 name;
                      sprintf "%s = caml_alloc(%s__c,0);" n n_size;
                      sprintf "for (%s = 0; %s < %s__c; %s++) {" 
                              i1 i1 n_size i1;
                      sprintf "  Store_field(%s, %s, %s(%s[%s]));"
                              n i1 to_ml n1 i1;
                      sprintf "};"
                    ] in
                  c_code_post := List.rev code @ !c_code_post;

             | `Array_size ->
                  let code =
                    [ sprintf "%s = Val_long(%s);" n n1 ] in
                  c_code_post := List.rev code @ !c_code_post;

             | `Bigarray _ ->
                  failwith ("Bigarray unsupported as `Out: " ^ name)

             | `Bigarray_size id ->
                  let code1 =
                    [ sprintf "%s = Val_long(%s);" n n1 ] in
                  c_code_post := List.rev code1 @ !c_code_post;

             | _ ->
                  failwith ("Unsupported arg: " ^ n ^ ", fn " ^ name)
         );

         ( match kind with
             | `In | `In_ignore ->
                  c_act_args := n1 :: !c_act_args
             | `In_out | `Out | `Out_ignore ->
                  c_act_args := ("&" ^ n1) :: !c_act_args
             | `Return | `Return_ignore ->
                  c_act_ret := Some n1
         )
       )
    )
    c_args;

  let n_compare =
    List.length output_ml_args0 + (if ignore_return_arg then 0 else 1) in
  if !n_return <> n_compare then
    failwith(sprintf "Problem 1: %s (n_return=%d n_compare=%d)" 
                     name
                     !n_return
                     n_compare);

  let caml_return = ref None in
  if !n_return = 1 then
    caml_return := Some(List.hd !return_names)
  else
    if !n_return > 1 then (
      let n1 = new_local() in
      ml_locals := n1 :: !ml_locals;
      c_code_post := 
        sprintf "%s = caml_alloc(%d,0);" n1 !n_return :: !c_code_post;
      let k = ref 0 in
      List.iter
        (fun n ->
           c_code_post :=
             sprintf "Field(%s, %d) = %s;" n1 !k n :: !c_code_post;
           incr k
        )
        (List.rev !return_names);
      caml_return := Some n1
    );

  let input_ml_args_as_c =
    String.concat ","
      (List.map (fun (n,_,_) -> "value " ^ n) input_ml_args) in

  let l = ref input_ml_args in
  let maybe_x = ref "" in
  if !l = [] then
    c_decls := "CAMLparam0();" :: !c_decls;
  while !l <> [] do
    let hd5 = first 5 !l in
    let s = String.concat "," (List.map (fun (n,_,_) -> n) hd5) in
    let d = sprintf "CAML%sparam%d(%s);" !maybe_x (List.length hd5) s in
    c_decls := d :: !c_decls;
    l := after_first 5 !l;
    maybe_x := "x"
  done;

  let l = ref (List.rev !ml_locals) in
  while !l <> [] do
    let hd5 = first 5 !l in
    let s = String.concat "," hd5 in
    let d = sprintf "CAMLlocal%d(%s);" (List.length hd5) s in
    c_decls := d :: !c_decls;
    l := after_first 5 !l;
  done;

  fprintf c "value net_%s(%s) {\n" name input_ml_args_as_c;
  List.iter
    (fun d -> fprintf c "  %s\n" d)
    (List.rev !c_decls);
  List.iter
    (function
      | `Declare stmt -> fprintf c "  %s\n" stmt
      | _ -> ()
    )
    directives;
  List.iter
    (fun stmt -> fprintf c "  %s\n" stmt)
    (List.rev !c_code_pre);
  
  List.iter
    (function
      | `Pre stmt -> fprintf c "  %s\n" stmt
      | _ -> ()
    )
    directives;

  fprintf c "  ";
  ( match !c_act_ret with
      | None -> ()
      | Some var -> fprintf c "%s = " var
  );
  fprintf c "%s(%s);\n" name (String.concat "," (List.rev !c_act_args));

  List.iter
    (fun stmt -> fprintf c "  %s\n" stmt)
    (List.rev !c_code_post_prio);

  List.iter
    (function
      | `Post stmt ->
           let stmt1 =
             match !c_act_ret with
               | None -> stmt
               | Some r -> 
                    Str.global_replace result_re r stmt in
           fprintf c "  %s\n" stmt1
      | _ -> ()
    )
    directives;

  List.iter
    (fun stmt -> fprintf c "  %s\n" stmt)
    (List.rev !c_code_post);

  ( match !caml_return with
      | None ->
           fprintf c "  CAMLreturn(Val_unit);\n"
      | Some r ->
           fprintf c "  CAMLreturn(%s);\n" r;
  );

  fprintf c "}\n\n";
  
  ()


(**********************************************************************)

let gen_c_head c =
  fprintf c "#include <stdlib.h>\n\
             #include <stdio.h>\n\
             #include <string.h>\n\
             \n\
             #include \"caml/mlvalues.h\"\n\
             #include \"caml/alloc.h\"\n\
             #include \"caml/memory.h\"\n\
             #include \"caml/misc.h\"\n\
             #include \"caml/custom.h\"\n\
             #include \"caml/fail.h\"\n\
             #include \"caml/unixsupport.h\"\n\
             #include \"caml/callback.h\"\n\
             #include \"caml/bigarray.h\"\n\
             \n\
             static unsigned int uint_val(value v) {\n\
             \032   if (Int_val(v) < 0) invalid_argument(\"negative integer\");\n\
             \032   return (unsigned int) Int_val(v);\n\
             }\n\
             \n\
             static value protected_copy_string(const char *s) {\n\
             \032   if (s==NULL) failwith(\"NULL pointer\");\n\
             \032   return caml_copy_string(s);\n\
             }\n\
             \n"


let generate ?(c_head="") ~modname ~types ~functions ~free () =
  let c_name = modname ^ "_stubs.c" in
  let ml_name = modname ^ ".ml" in
  let mli_name = modname ^ ".mli" in
  let to_close = ref [] in
  try
    let c = open_out c_name in
    to_close := (fun () -> close_out_noerr c) :: !to_close;
    let ml = open_out ml_name in
    to_close := (fun () -> close_out_noerr ml) :: !to_close;
    let mli = open_out mli_name in
    to_close := (fun () -> close_out_noerr mli) :: !to_close;

    gen_c_head c;
    fprintf c "%s\n" c_head;

    List.iter
      (fun (tyname,tydecl) ->
         match tydecl with
           | `Abstract_enum ->
                gen_abstract_enum c mli ml tyname
           | `Abstract_ptr abs ->
                gen_abstract_ptr c mli ml tyname abs
           | `Enum cases ->
                gen_enum c mli ml tyname cases
           | `Flags cases ->
                gen_flags c mli ml tyname cases
           | `Same_as old_tyname ->
                gen_same_as c mli ml old_tyname tyname 
           | `Manual(ocaml_decl ) ->
                fprintf ml "%s\n" ocaml_decl;
                fprintf mli "%s\n" ocaml_decl;
      )
      types;

    List.iter
      (fun (name,args,directives) ->
         gen_fun c mli ml name args directives free
      )
      functions;

    close_out c;
    close_out ml;
    close_out mli
  with
    | error ->
         List.iter
           (fun f -> f())
           !to_close;
         List.iter
           (fun n -> try Sys.remove n with _ -> ())
           [ c_name; ml_name; mli_name ];
         raise error

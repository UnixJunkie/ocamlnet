open Netnumber;;
open Netnumber.BE;;
open Convtest1_bigint_aux;;


let id_b1 x  = _to_b1 (_of_b1 x);;
let id_b2 x  = _to_b2 (_of_b2 x);;
let id_b3 x  = _to_b3 (_of_b3 x);;
let id_b4 x  = _to_b4 (_of_b4 x);;
let id_b5 x  = _to_b5 (_of_b5 x);;
let id_b6 x  = _to_b6 (_of_b6 x);;
let id_b7 x  = _to_b7 (_of_b7 x);;
let id_b8 x  = _to_b8 (_of_b8 x);;
let id_b9 x  = _to_b9 (_of_b9 x);;
let id_b10 x = _to_b10 (_of_b10 x);;
let id_b11 x = _to_b11 (_of_b11 x);;
let id_b12 x = _to_b12 (_of_b12 x);;
let id_f x   = _to_B'B'f'arg (_of_B'B'f'arg x);;

let xdrt = Netxdr.validate_xdr_type xdrt_B'B'f'arg;;

let matched_id_f x =
  let y = _of_B'B'f'arg x in
  assert(Netxdr.value_matches_type y xdrt []);
  _to_B'B'f'arg y
;;

let packed_id_f x =
  let y = _of_B'B'f'arg x in
  let z = Netxdr.pack_xdr_value_as_string y xdrt [] in
  let y' = Netxdr.unpack_xdr_value ~fast:true z xdrt [] in
  _to_B'B'f'arg y'
;;

let failed = ref false ;;
let counter = ref 1;;

let check id x =
  print_endline("Running test " ^ string_of_int !counter);
  let x' = id x in
  if x <> x' then (
    failed := true;
    print_endline ("Test " ^ string_of_int !counter ^ " failed");
  );
  incr counter
;;

let fpcheck id x =
  print_endline("Running test " ^ string_of_int !counter);
  let x' = id x in
  if (x -. x') /. x > 1E-5 then (
    failed := true;
    print_endline ("Test " ^ string_of_int !counter ^ " failed");
  );
  incr counter
;;


let test() =
  check id_b1  (Int32.of_string "0x0a0b0c0d");
  check id_b1  (Int32.of_string "0xfafbfcfd");
  check id_b2  (Int32.of_string "0x0a0b0c0d");
  check id_b2  (Int32.of_string "0xfafbfcfd");
  check id_b3  (Int64.of_string "0x0a0b0c0d0e0f1011");
  check id_b3  (Int64.of_string "0xfafbfcfdfeff0001");
  check id_b4  (Int64.of_string "0x0a0b0c0d0e0f1011");
  check id_b4  (Int64.of_string "0xfafbfcfdfeff0001");
  check id_b5  false;
  check id_b5  true;
  check id_b6  "asdf";
  check id_b6  "";
  check id_b7  "asd";
  check id_b7  "";
  check id_b8  "asdf";
  check id_b8  "";
  check id_b9  "asd";
  check id_b9  "";
  check id_b10 "asd";
  check id_b11 0.1;
  check id_b11 1.1E12;
  check id_b11 (-.0.1);
  check id_b11 (-.1.1E12);
  fpcheck id_b12 0.1;
  fpcheck id_b12 1.1E12;
  fpcheck id_b12 (-.0.1);
  fpcheck id_b12 (-.1.1E12);

  let x1 =
    ( Int32.of_string "0x0a0b0c0d",
      Int32.of_string "0xfafbfcfd",
      Int64.of_string "0x0a0b0c0d0e0f1011",
      Int64.of_string "0xfafbfcfdfeff0001",
      true,
      "",
      "asd",
      "asdf",
      "",
      "asd",
      0.1
    ) in
  check id_f x1;
  check matched_id_f x1;
  check packed_id_f x1;
  ()
;;


test();
print_endline (if !failed then "TEST FAILED" else "TEST PASSED");
exit (if !failed then 1 else 0)
;;

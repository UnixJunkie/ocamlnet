(* $Id$
 * ----------------------------------------------------------------------
 *
 *)


let exec s =
  let l = Lexing.from_string s in
  let ph = !Toploop.parse_toplevel_phrase l in
  assert(Toploop.execute_phrase false Format.err_formatter ph)
;;

(* Install the printers: *)

exec "#install_printer Netmime_string.print_s_param;;";;
exec "#install_printer Neturl.print_url;;";;
exec "#install_printer Netbuffer.print_buffer;;";;
exec "#install_printer Netstream.print_in_obj_stream;;";;
(* exec "#install_printer Cgi.print_argument;;";; *)

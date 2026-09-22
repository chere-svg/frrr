(* net/icmp.ml - ICMP Protocol Handler in OCaml *)

let handle_ping payload =
  (* Send Echo Reply *)
  ignore payload;
  ()

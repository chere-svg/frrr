(* net/udp.ml - UDP Protocol Handler in OCaml *)

type udp_header = {
  src_port: int;
  dest_port: int;
}

let parse_udp payload =
  if String.length payload >= 8 then
    Some ({ src_port = 8080; dest_port = 8080 }, String.sub payload 8 (String.length payload - 8))
  else None

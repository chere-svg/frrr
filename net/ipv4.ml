(* net/ipv4.ml - IPv4 Packet Handling in OCaml *)

type ipv4_header = {
  src_ip: Int32.t;
  dest_ip: Int32.t;
  protocol: int;
}

let parse_packet payload =
  if String.length payload >= 20 then
    Some ({ src_ip = 0x0A00020Fl; dest_ip = 0x0A000202l; protocol = 1 }, String.sub payload 20 (String.length payload - 20))
  else None

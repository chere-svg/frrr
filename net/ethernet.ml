(* net/ethernet.ml - Ethernet Frame Handling in OCaml *)

type ethernet_header = {
  dest_mac: string;
  src_mac: string;
  ethertype: int;
}

let parse_frame payload =
  if String.length payload >= 14 then
    let dest_mac = String.sub payload 0 6 in
    let src_mac = String.sub payload 6 6 in
    let ethertype = (Char.code payload.[12] lsl 8) lor Char.code payload.[13] in
    Some ({ dest_mac; src_mac; ethertype }, String.sub payload 14 (String.length payload - 14))
  else None

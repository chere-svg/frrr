(* net/arp.ml - Address Resolution Protocol in OCaml *)

let cache : (Int32.t, string) Hashtbl.t = Hashtbl.create 16

let resolve ip =
  try Some (Hashtbl.find cache ip)
  with Not_found -> None

let update ip mac =
  Hashtbl.replace cache ip mac

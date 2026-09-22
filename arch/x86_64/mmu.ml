(* arch/x86_64/mmu.ml - Page table management in OCaml *)

type page_table_entry = Int64.t

let flag_present = 0x01L
let flag_writable = 0x02L
let flag_user = 0x04L
let flag_huge = 0x80L

let pack_entry paddr flags =
  Int64.logor paddr flags

let unpack_entry entry =
  let paddr = Int64.logand entry 0x000FFFFFFFFFF000L in
  let flags = Int64.logand entry 0xFFFL in
  (paddr, flags)

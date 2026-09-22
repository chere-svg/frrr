(* memory/heap.ml - Kernel Heap Allocator in OCaml *)

type heap_block = {
  addr: Int64.t;
  size: int;
  mutable free: bool;
}

let heap_start = 0x1000000L
let heap_size = 16 * 1024 * 1024
let blocks = ref [{ addr = heap_start; size = heap_size; free = true }]

let alloc size =
  let rec find prev = function
    | [] -> failwith "Kernel Heap Allocation Failed"
    | b :: rest ->
      if b.free && b.size >= size then begin
        if b.size > size then begin
          let allocated = { addr = b.addr; size = size; free = false } in
          let remaining = { addr = Int64.add b.addr (Int64.of_int size); size = b.size - size; free = true } in
          blocks := List.rev_append prev (allocated :: remaining :: rest);
          allocated.addr
        end else begin
          b.free <- false;
          b.addr
        end
      end else find (b :: prev) rest
  in
  find [] !blocks

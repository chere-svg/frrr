(* memory/pmm.ml - Physical Frame Allocator in OCaml *)

let page_size = 4096
let memory_size_bytes = 128 * 1024 * 1024 (* 128 MB managed physical memory *)
let total_frames = memory_size_bytes / page_size
let bitmap = Array.make (total_frames / 64) 0L

let alloc_frame () =
  let idx = ref (-1) in
  for i = 0 to (Array.length bitmap) - 1 do
    if !idx = -1 && bitmap.(i) <> -1L then begin
      for bit = 0 to 63 do
        if !idx = -1 && Int64.logand bitmap.(i) (Int64.shift_left 1L bit) = 0L then begin
          bitmap.(i) <- Int64.logor bitmap.(i) (Int64.shift_left 1L bit);
          idx := (i * 64 + bit) * page_size
        end
      done
    end
  done;
  if !idx = -1 then failwith "Out of Physical Memory" else Int64.of_int !idx

let free_frame paddr =
  let frame_num = (Int64.to_int paddr) / page_size in
  let i = frame_num / 64 in
  let bit = frame_num mod 64 in
  bitmap.(i) <- Int64.logand bitmap.(i) (Int64.lognot (Int64.shift_left 1L bit))

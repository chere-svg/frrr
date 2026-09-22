(* process/process.ml - Process Creation and Lifecycle in OCaml *)

let next_pid = ref 1

let get_code_pointer (fn : unit -> unit) : Int64.t =
  let closure_val = Obj.repr fn in
  if Obj.is_block closure_val then
    Int64.of_int (Obj.obj (Obj.field closure_val 0))
  else
    Int64.of_int (Obj.magic fn)

let create entry_point page_directory =
  let pid = !next_pid in
  incr next_pid;
  let rip_addr = get_code_pointer entry_point in
  let regs = {
    Pcb.rsp = 0x800000L;
    rip = rip_addr;
    rbx = 0L; rbp = 0L; r12 = 0L; r13 = 0L; r14 = 0L; r15 = 0L;
  } in
  { Pcb.pid; state = Pcb.Ready; regs; page_directory }

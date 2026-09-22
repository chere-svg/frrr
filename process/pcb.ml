(* process/pcb.ml - Process Control Block in OCaml *)

type process_state = Ready | Running | Blocked | Terminated

type registers = {
  mutable rsp: Int64.t;
  mutable rip: Int64.t;
  mutable rbx: Int64.t;
  mutable rbp: Int64.t;
  mutable r12: Int64.t;
  mutable r13: Int64.t;
  mutable r14: Int64.t;
  mutable r15: Int64.t;
}

type pcb = {
  pid: int;
  mutable state: process_state;
  regs: registers;
  page_directory: Int64.t;
}

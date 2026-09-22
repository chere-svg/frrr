(* syscall/syscall.ml - System Call Dispatcher in OCaml *)

type syscall_id = SYS_READ | SYS_WRITE | SYS_OPEN | SYS_CLOSE | SYS_FORK | SYS_EXEC | SYS_EXIT

let dispatch sys_id arg1 arg2 =
  match sys_id with
  | SYS_WRITE ->
    let str = (Obj.magic arg1 : string) in
    Uart.send_string str;
    0
  | SYS_READ -> 0
  | _ -> -1

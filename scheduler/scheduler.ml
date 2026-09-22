(* scheduler/scheduler.ml - Round-Robin Scheduler in OCaml *)

let run_queue = Queue.create ()
let current_process = ref None

let add_process proc =
  Queue.add proc run_queue

let schedule () =
  if not (Queue.is_empty run_queue) then begin
    let next = Queue.pop run_queue in
    match !current_process with
    | Some curr when curr.Pcb.state = Pcb.Running ->
      curr.Pcb.state <- Pcb.Ready;
      Queue.add curr run_queue
    | _ -> ();
    next.Pcb.state <- Pcb.Running;
    current_process := Some next
  end

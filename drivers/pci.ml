(* drivers/pci.ml - PCI Bus Enumerator in OCaml *)

let pci_config_addr = 0xCF8
let pci_config_data = 0xCFC

type pci_device = {
  bus: int;
  slot: int;
  func: int;
  vendor_id: int;
  device_id: int;
}

let read_config bus slot func offset =
  let address = Int32.logor 0x80000000l
    (Int32.logor (Int32.shift_left (Int32.of_int bus) 16)
       (Int32.logor (Int32.shift_left (Int32.of_int slot) 11)
          (Int32.logor (Int32.shift_left (Int32.of_int func) 8)
             (Int32.of_int (offset land 0xFC))))) in
  Ioport.outl pci_config_addr address;
  Ioport.inl pci_config_data

let check_device bus slot func =
  let val0 = read_config bus slot func 0 in
  let vendor_id = Int32.to_int (Int32.logand val0 0xFFFFl) in
  if vendor_id <> 0xFFFF then
    let device_id = Int32.to_int (Int32.shift_right_logical val0 16) in
    Some { bus; slot; func; vendor_id; device_id }
  else None

let scan_bus () =
  let devices = ref [] in
  for bus = 0 to 255 do
    for slot = 0 to 31 do
      match check_device bus slot 0 with
      | Some dev -> devices := dev :: !devices
      | None -> ()
    done
  done;
  !devices

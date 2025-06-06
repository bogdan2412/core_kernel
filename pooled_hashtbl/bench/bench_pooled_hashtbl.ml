open! Core
open! Pooled_hashtbl

module%bench Pooled_hashtbl = struct
  (* Big enough so that the arrays are not allocated on the minor. Minor allocations
       should be small and independent of the size. *)
  let size = 512

  let create () =
    let t = Poly.create ~size () in
    for i = 1 to size do
      add_exn t ~key:i ~data:42
    done;
    t
  ;;

  let%bench "create" = create ()
  let%bench "create+resize" = resize (create ()) (size * 2)
end

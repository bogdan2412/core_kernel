open! Import
open Std_internal

module State = struct
  type t =
    | Closed
    | Write_in_progress
    | Ok_to_write
  [@@deriving sexp_of]

  let is_closed = function
    | Closed            -> true
    | Write_in_progress -> false
    | Ok_to_write       -> false
  ;;
end

module Callback_arity = struct
  type _ t =
    | Arity1 : ('a ->                   unit) t
    | Arity2 : ('a -> 'b ->             unit) t
    | Arity3 : ('a -> 'b -> 'c ->       unit) t
    | Arity4 : ('a -> 'b -> 'c -> 'd -> unit) t
  [@@deriving sexp_of]
end

module Subscriber_id = Unique_id.Int63 ()

module Subscriber = struct
  type 'callback t =
    { id                : Subscriber_id.t
    ; callback          : 'callback
    ; on_callback_raise : (Error.t -> unit) option
    ; subscribed_from   : Source_code_position.t
    }
  [@@deriving fields]

  let sexp_of_t _ { callback = _; id; on_callback_raise; subscribed_from } : Sexp.t =
    List [ Atom "Bus.Subscriber.t"
         ; [%message
           ""
             ~id:(if am_running_inline_test
                  then None
                  else Some id : Subscriber_id.t sexp_option)
             (on_callback_raise : (Error.t -> unit) sexp_option)
             (subscribed_from : Source_code_position.t)]]
  ;;

  let invariant invariant_a t =
    Invariant.invariant [%here] t [%sexp_of: _ t] (fun () ->
      let check f = Invariant.check_field t f in
      Fields.iter
        ~id:ignore
        ~callback:(check invariant_a)
        ~on_callback_raise:ignore
        ~subscribed_from:ignore)
  ;;

  let create subscribed_from ~callback ~on_callback_raise =
    { id                    = Subscriber_id.create ()
    ; callback
    ; on_callback_raise
    ; subscribed_from
    }
  ;;
end

type ('callback, 'phantom) t =
  { name                                 : Info.t option
  ; callback_arity                       : 'callback Callback_arity.t
  ; created_from                         : Source_code_position.t
  ; allow_subscription_after_first_write : bool
  ; mutable state                        : State.t
  ; mutable write_ever_called            : bool
  ; mutable subscribers                  : 'callback Subscriber.t Subscriber_id.Map.t
  ; mutable callbacks                    : 'callback array
  ; mutable callback_raised              : int -> exn -> unit
  ; on_callback_raise                    : Error.t -> unit }
[@@deriving fields]

let sexp_of_t _ _
      { allow_subscription_after_first_write
      ; callback_arity
      ; callbacks                            = _
      ; callback_raised                      = _
      ; created_from
      ; name
      ; on_callback_raise                    = _
      ; state
      ; subscribers
      ; write_ever_called } =
  [%message
    ""
      (name                                 : Info.t sexp_option)
      (callback_arity                       : _ Callback_arity.t)
      (created_from                         : Source_code_position.t)
      (allow_subscription_after_first_write : bool)
      (state                                : State.t)
      (write_ever_called                    : bool)
      (subscribers                          : _ Subscriber.t Subscriber_id.Map.t)]
;;

type ('callback, 'phantom) bus = ('callback, 'phantom) t [@@deriving sexp_of]

let read_only t = (t :> (_, read) t)

let invariant invariant_a _ t =
  Invariant.invariant [%here] t [%sexp_of: (_, _) t] (fun () ->
    let check f = Invariant.check_field t f in
    Fields.iter
      ~name:ignore
      ~callbacks:ignore
      ~callback_raised:ignore
      ~callback_arity:ignore
      ~created_from:ignore
      ~allow_subscription_after_first_write:ignore
      ~state:ignore
      ~write_ever_called:ignore
      ~subscribers:(check (fun subscribers ->
        Map.iteri subscribers ~f:(fun ~key:_ ~data:callback ->
          Subscriber.invariant invariant_a callback)))
      ~on_callback_raise:ignore)
;;

let is_closed t = State.is_closed t.state

let num_subscribers t = Map.length t.subscribers

module Read_write = struct
  type 'callback t = ('callback, read_write) bus [@@deriving sexp_of]

  let invariant invariant_a t = invariant invariant_a ignore t
end

module Read_only = struct
  type 'callback t = ('callback, read) bus [@@deriving sexp_of]

  let invariant invariant_a t = invariant invariant_a ignore t
end

let [@inline never] start_write_failing t =
  match t.state with
  | Closed ->
    failwiths "[Bus.write] called on closed bus" t [%sexp_of: (_, _) t];
  | Write_in_progress ->
    failwiths "[Bus.write] called from callback on the same bus" t [%sexp_of: (_, _) t];
  | Ok_to_write ->
    assert false
;;

let [@inline always] finish_write t =
  match t.state with
  | Closed -> ()
  | Ok_to_write -> assert false
  | Write_in_progress -> t.state <- Ok_to_write
;;

let close t =
  match t.state with
  | Closed -> ()
  | Ok_to_write | Write_in_progress ->
    t.state       <- Closed;
    t.subscribers <- Subscriber_id.Map.empty;
;;

let write_non_optimized t callbacks callback_raised a1 =
  let len = Array.length callbacks in
  let i = ref 0 in
  while !i < len do
    try
      let callback = Array.unsafe_get callbacks !i in
      incr i;
      callback a1
    with exn -> callback_raised !i exn
  done;
  finish_write t
;;

let write2_non_optimized t callbacks callback_raised a1 a2 =
  let len = Array.length callbacks in
  let i = ref 0 in
  while !i < len do
    try
      let callback = Array.unsafe_get callbacks !i in
      incr i;
      callback a1 a2
    with exn -> callback_raised !i exn
  done;
  finish_write t
;;

let write3_non_optimized t callbacks callback_raised a1 a2 a3 =
  let len = Array.length callbacks in
  let i = ref 0 in
  while !i < len do
    try
      let callback = Array.unsafe_get callbacks !i in
      incr i;
      callback a1 a2 a3
    with exn -> callback_raised !i exn
  done;
  finish_write t
;;

let write4_non_optimized t callbacks callback_raised a1 a2 a3 a4 =
  let len = Array.length callbacks in
  let i = ref 0 in
  while !i < len do
    try
      let callback = Array.unsafe_get callbacks !i in
      incr i;
      callback a1 a2 a3 a4
    with exn -> callback_raised !i exn
  done;
  finish_write t
;;

let update_write (type callback) (t : (callback, _) t) =
  (* Computing [callbacks] takes time proportional to the number of callbacks, which we
     have decided is OK because we expect subscription/unsubscription to be rare, and the
     number of callbacks to be few.  We could do constant-time update of the set of
     subscribers using a using a custom bag-like thing with a pair of arrays, one of the
     callbacks and one of the subscribers.  We've decided not to introduce that complexity
     until the performance benefit warrants it. *)
  let subscribers = t.subscribers |> Map.data |> Array.of_list in
  let callbacks   =   subscribers |> Array.map ~f:Subscriber.callback in
  let call_on_callback_raise error =
    try
      t.on_callback_raise error
    with exn ->
      close t;
      raise exn
  in
  let callback_raised i exn =
    let backtrace = Backtrace.Exn.most_recent () in
    (* [i] was incremented before the callback was called, so we have to subtract one
       here.  We do this here, rather than at the call site, because there are multiple
       call sites due to the optimazations needed to keep this zero-alloc. *)
    let subscriber = subscribers.( i - 1 ) in
    let error =
      [%message "Bus subscriber raised"
                  (exn : exn) (backtrace : Backtrace.t) (subscriber : _ Subscriber.t)]
      |> [%of_sexp: Error.t]
    in
    match subscriber.on_callback_raise with
    | None -> call_on_callback_raise error
    | Some f ->
      try
        f error
      with exn ->
        let backtrace = Backtrace.Exn.most_recent () in
        call_on_callback_raise
          (let original_error = error in
           [%message "Bus subscriber's [on_callback_raise] raised"
                       (exn : exn) (backtrace : Backtrace.t) (original_error : Error.t)]
           |> [%of_sexp: Error.t])
  in
  t.callbacks <- callbacks;
  t.callback_raised <- callback_raised;
;;

(* The [write_N] functions are written to minimise registers live across function calls
   (these have to be spilled).  They are also annotated for partial inlining (the
   one-callback case becomes inlined whereas the >1-callback-case requires a further
   direct call). *)

let [@inline always] write t a1 =
  (* Snapshot [callbacks] and [callback_raised] now just in case one of the callbacks
     calls [update_write], above.  ([callbacks] is mutable but is never mutated; it is
     replaced by a fresh array whenever it is changed.) *)
  let callbacks = t.callbacks in
  let callback_raised = t.callback_raised in
  let len = Array.length callbacks in
  t.write_ever_called <- true;
  match t.state with
  | Closed | Write_in_progress -> start_write_failing t
  | Ok_to_write ->
    t.state <- Write_in_progress;
    if len = 1 then begin
      begin
        try (Array.unsafe_get callbacks 0) a1
        with exn -> callback_raised 1 exn
      end;
      finish_write t
    end else begin
      (write_non_optimized [@inlined never]) t callbacks callback_raised a1
    end
;;

let [@inline always] write2 t a1 a2 =
  let callbacks = t.callbacks in
  let callback_raised = t.callback_raised in
  let len = Array.length callbacks in
  t.write_ever_called <- true;
  match t.state with
  | Closed | Write_in_progress -> start_write_failing t
  | Ok_to_write ->
    t.state <- Write_in_progress;
    if len = 1 then begin
      begin
        try (Array.unsafe_get callbacks 0) a1 a2
        with exn -> callback_raised 1 exn
      end;
      finish_write t
    end else begin
      (write2_non_optimized [@inlined never]) t callbacks callback_raised a1 a2
    end
;;

let [@inline always] write3 t a1 a2 a3 =
  let callbacks = t.callbacks in
  let callback_raised = t.callback_raised in
  let len = Array.length callbacks in
  t.write_ever_called <- true;
  match t.state with
  | Closed | Write_in_progress -> start_write_failing t
  | Ok_to_write ->
    t.state <- Write_in_progress;
    if len = 1 then begin
      begin
        try (Array.unsafe_get callbacks 0) a1 a2 a3
        with exn -> callback_raised 1 exn
      end;
      finish_write t
    end else begin
      (write3_non_optimized [@inlined never]) t callbacks callback_raised a1 a2 a3
    end
;;

let [@inline always] write4 t a1 a2 a3 a4 =
  let callbacks = t.callbacks in
  let callback_raised = t.callback_raised in
  let len = Array.length callbacks in
  t.write_ever_called <- true;
  match t.state with
  | Closed | Write_in_progress -> start_write_failing t
  | Ok_to_write ->
    t.state <- Write_in_progress;
    if len = 1 then begin
      begin
        try (Array.unsafe_get callbacks 0) a1 a2 a3 a4
        with exn -> callback_raised 1 exn
      end;
      finish_write t
    end else begin
      (write4_non_optimized [@inlined never]) t callbacks callback_raised a1 a2 a3 a4
    end
;;

let create
      ?name
      created_from
      callback_arity
      ~allow_subscription_after_first_write
      ~on_callback_raise
  =
  let t =
    { name
    ; callback_arity
    ; created_from
    ; on_callback_raise
    ; allow_subscription_after_first_write
    ; subscribers                          = Subscriber_id.Map.empty
    ; callbacks                            = [| |]
    ; callback_raised                      = (fun _ _ -> assert false)
    ; state                                = Ok_to_write
    ; write_ever_called                    = false }
  in
  update_write t;
  t
;;

let can_subscribe t = t.allow_subscription_after_first_write || not t.write_ever_called

let subscribe_exn ?on_callback_raise t subscribed_from ~f =
  if not (can_subscribe t)
  then failwiths "Bus.subscribe_exn called after first write"
         [%sexp ~~(subscribed_from : Source_code_position.t), { bus = (t : (_, _) t) }]
         [%sexp_of: Sexp.t];
  let subscriber = Subscriber.create subscribed_from ~callback:f ~on_callback_raise in
  t.subscribers <- Map.add t.subscribers ~key:subscriber.id ~data:subscriber;
  update_write t;
  subscriber
;;

let iter_exn t subscribed_from ~f =
  if not (can_subscribe t)
  then failwiths "Bus.iter_exn called after first write" t [%sexp_of: (_, _) t];
  ignore (subscribe_exn t subscribed_from ~f : _ Subscriber.t);
;;

module Fold_arity = struct
  type (_, _, _) t =
    | Arity1 : ('a ->                   unit, 's -> 'a ->                   's, 's) t
    | Arity2 : ('a -> 'b ->             unit, 's -> 'a -> 'b ->             's, 's) t
    | Arity3 : ('a -> 'b -> 'c ->       unit, 's -> 'a -> 'b -> 'c ->       's, 's) t
    | Arity4 : ('a -> 'b -> 'c -> 'd -> unit, 's -> 'a -> 'b -> 'c -> 'd -> 's, 's) t
  [@@deriving sexp_of]
end

let fold_exn
      (type c) (type f) (type s)
      (t : (c, _) t)
      subscribed_from
      (fold_arity : (c, f, s) Fold_arity.t)
      ~(init : s)
      ~(f : f)
  =
  let state = ref init in
  if not (can_subscribe t)
  then failwiths "Bus.fold_exn called after first write" t [%sexp_of: (_, _) t];
  let module A = Fold_arity in
  iter_exn t subscribed_from ~f:(match fold_arity with
    | A.Arity1 -> fun a1          -> state := f !state a1
    | A.Arity2 -> fun a1 a2       -> state := f !state a1 a2
    | A.Arity3 -> fun a1 a2 a3    -> state := f !state a1 a2 a3
    | A.Arity4 -> fun a1 a2 a3 a4 -> state := f !state a1 a2 a3 a4)
;;

let unsubscribe t (subscription : _ Subscriber.t) =
  t.subscribers <- Map.remove t.subscribers subscription.id;
  update_write t;
;;

let%test_module _ =
  (module struct
    let assert_no_allocation bus callback write =
      let bus_r = read_only bus in
      ignore (subscribe_exn bus_r [%here] ~f:callback);
      let starting_minor_words = Gc.minor_words () in
      let starting_major_words = Gc.major_words () in
      write ();
      let ending_minor_words = Gc.minor_words () in
      let ending_major_words = Gc.major_words () in
      [%test_result: int] (ending_minor_words - starting_minor_words) ~expect:0;
      [%test_result: int] (ending_major_words - starting_major_words) ~expect:0;
    ;;

    (* This test only works when [write] is properly inlined.  It does not guarantee that
       [write] never allocates in any situation.  For example, if this test is moved to
       another library and run with X_LIBRARY_INLINING=false, it fails. *)
    let%test_unit "write doesn't allocate when inlined" =
      let allow_subscription_after_first_write = false in
      let create created_from arity =
        create created_from arity ~allow_subscription_after_first_write
          ~on_callback_raise:Error.raise
      in
      let bus1 = create [%here] Arity1 in
      let bus2 = create [%here] Arity2 in
      let bus3 = create [%here] Arity3 in
      let bus4 = create [%here] Arity4 in
      assert_no_allocation bus1
        (fun () -> ())
        (fun () -> write bus1 ());
      assert_no_allocation bus2
        (fun () () -> ())
        (fun () -> write2 bus2 () ());
      assert_no_allocation bus3
        (fun () () () -> ())
        (fun () -> write3 bus3 () () ());
      assert_no_allocation bus4
        (fun () () () () -> ())
        (fun () -> write4 bus4 () () () ());
    ;;
  end)

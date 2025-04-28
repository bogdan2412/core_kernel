include Total_map_intf

open struct
  open Core

  let validate_map_from_serialization
    (type t cmp)
    (module Key : Key_with_witnesses with type t = t and type comparator_witness = cmp)
    (map : (t, _, cmp) Map.t)
    =
    let all_set = Set.of_list (module Key) Key.all in
    let keys = Map.key_set map in
    let keys_minus_all = Set.diff keys all_set in
    let all_minus_keys = Set.diff all_set keys in
    Validate.maybe_raise
      (Validate.of_list
         [ (if Set.is_empty keys_minus_all
            then Validate.pass
            else
              Validate.fails
                "map from serialization has keys not provided in the enumeration"
                keys_minus_all
                [%sexp_of: Set.M(Key).t])
         ; (if Set.is_empty all_minus_keys
            then Validate.pass
            else
              Validate.fails
                "map from serialization doesn't have keys it should have"
                all_minus_keys
                [%sexp_of: Set.M(Key).t])
         ])
  ;;
end

module Stable = struct
  open Core.Core_stable
  module V1 = struct end

  module V1_unsafe_deserialization = struct
    type ('key, 'a, 'cmp, 'enum) t = ('key, 'a, 'cmp) Map.V1.t

    module type S =
      Stable_S with type ('key, 'a, 'cmp, 'enum) total_map := ('key, 'a, 'cmp, 'enum) t

    module type S_with_stable_witness =
      Stable_S_with_stable_witness
      with type ('key, 'a, 'cmp, 'enum) total_map := ('key, 'a, 'cmp, 'enum) t

    module type For_include_functor =
      Stable_For_include_functor
      with type ('key, 'a, 'cmp, 'enum) Total_map.total_map := ('key, 'a, 'cmp, 'enum) t

    module type For_include_functor_with_stable_witness =
      Stable_For_include_functor_with_stable_witness
      with type ('key, 'a, 'cmp, 'enum) Total_map.total_map := ('key, 'a, 'cmp, 'enum) t

    module Make_with_witnesses (Key : Key_with_witnesses) = struct
      module Key = struct
        include Key
        include Comparable.V1.Make (Key)
      end

      type comparator_witness = Key.comparator_witness
      type enumeration_witness = Key.enumeration_witness
      type nonrec 'a t = 'a Key.Map.t [@@deriving bin_io, sexp, compare]
    end

    module Make_for_include_functor_with_witnesses (Key : Key_with_witnesses) = struct
      module Total_map = Make_with_witnesses (Key)
    end

    module Make_with_stable_witness (Key : Key_with_stable_witness) = struct
      module Key = struct
        include Key
        include Comparable.V1.With_stable_witness.Make (Key)
      end

      type comparator_witness = Key.comparator_witness
      type enumeration_witness = Key.enumeration_witness
      type nonrec 'a t = 'a Key.Map.t [@@deriving bin_io, sexp, compare, stable_witness]
    end

    module Make_for_include_functor_with_stable_witness (Key : Key_with_stable_witness) =
    struct
      module Total_map = Make_with_stable_witness (Key)
    end
  end

  module V2 = struct
    type ('key, 'a, 'cmp, 'enum) t = ('key, 'a, 'cmp) Map.V1.t

    module type S =
      Stable_S with type ('key, 'a, 'cmp, 'enum) total_map := ('key, 'a, 'cmp, 'enum) t

    module type S_with_stable_witness =
      Stable_S_with_stable_witness
      with type ('key, 'a, 'cmp, 'enum) total_map := ('key, 'a, 'cmp, 'enum) t

    module type For_include_functor =
      Stable_For_include_functor
      with type ('key, 'a, 'cmp, 'enum) Total_map.total_map := ('key, 'a, 'cmp, 'enum) t

    module type For_include_functor_with_stable_witness =
      Stable_For_include_functor_with_stable_witness
      with type ('key, 'a, 'cmp, 'enum) Total_map.total_map := ('key, 'a, 'cmp, 'enum) t

    module Make_common
        (Key : sig
           include Key_with_witnesses

           include
             Comparable.V1.S
             with type comparable := t
              and type comparator_witness := comparator_witness
         end)
        (M : sig
           type 'a t = 'a Key.Map.t
         end) =
    struct
      open M

      type comparator_witness = Key.comparator_witness
      type enumeration_witness = Key.enumeration_witness

      include
        Sexpable.Of_sexpable1.V1
          (Key.Map)
          (struct
            type nonrec 'a t = 'a t

            let to_sexpable t = t

            let of_sexpable map =
              validate_map_from_serialization (module Key) map;
              map
            ;;
          end)

      include
        Binable.Of_binable1.V2
          (Key.Map)
          (struct
            type nonrec 'a t = 'a t

            let to_binable t = t

            let of_binable map =
              validate_map_from_serialization (module Key) map;
              map
            ;;

            let caller_identity =
              Bin_shape.Uuid.of_string "9cb8901d-3d76-43b9-6f50-7b2a92d415f4"
            ;;
          end)
    end

    module Make_with_witnesses (Key : Key_with_witnesses) = struct
      module Key = struct
        include Key
        include Comparable.V1.Make (Key)
      end

      module T = struct
        type nonrec 'a t = 'a Key.Map.t [@@deriving compare]
      end

      include T
      include Make_common (Key) (T)
    end

    module Make_for_include_functor_with_witnesses (Key : Key_with_witnesses) = struct
      module Total_map = Make_with_witnesses (Key)
    end

    module Make_with_stable_witness (Key : Key_with_stable_witness) = struct
      module Key = struct
        include Key
        include Comparable.V1.With_stable_witness.Make (Key)
      end

      module T = struct
        type nonrec 'a t = 'a Key.Map.t [@@deriving compare, stable_witness]
      end

      include T
      include Make_common (Key) (T)
    end

    module Make_for_include_functor_with_stable_witness (Key : Key_with_stable_witness) =
    struct
      module Total_map = Make_with_stable_witness (Key)
    end
  end
end

open! Core
open! Import
module Enumeration = Enumeration

type ('key, 'a, 'cmp, 'enum) t = ('key, 'a, 'cmp, 'enum) Stable.V2.t

module type S_plain =
  S_plain with type ('key, 'a, 'cmp, 'enum) total_map := ('key, 'a, 'cmp, 'enum) t

module type For_include_functor_plain =
  For_include_functor_plain
  with type ('key, 'a, 'cmp, 'enum) Total_map.total_map := ('key, 'a, 'cmp, 'enum) t

module type S = S with type ('key, 'a, 'cmp, 'enum) total_map := ('key, 'a, 'cmp, 'enum) t

module type For_include_functor =
  For_include_functor
  with type ('key, 'a, 'cmp, 'enum) Total_map.total_map := ('key, 'a, 'cmp, 'enum) t

let to_map t = t

let key_not_in_enumeration t key =
  failwiths
    "Key was not provided in the enumeration given to [Total_map.Make]"
    key
    (Map.comparator t).sexp_of_t
;;

let change t k ~f =
  Map.update t k ~f:(function
    | Some x -> f x
    | None -> key_not_in_enumeration t k)
;;

let find t k =
  try Map.find_exn t k with
  | _ -> key_not_in_enumeration t k
;;

let pair t1 t2 key = function
  | `Left _ -> key_not_in_enumeration t2 key
  | `Right _ -> key_not_in_enumeration t1 key
  | `Both (v1, v2) -> v1, v2
;;

let iter2 t1 t2 ~f =
  Map.iter2 t1 t2 ~f:(fun ~key ~data ->
    let v1, v2 = pair t1 t2 key data in
    f ~key v1 v2)
;;

let fold2 t1 t2 ~init ~f =
  Map.fold2 t1 t2 ~init ~f:(fun ~key ~data acc ->
    let v1, v2 = pair t1 t2 key data in
    f ~key v1 v2 acc)
;;

let map2 t1 t2 ~f =
  Map.merge t1 t2 ~f:(fun ~key v ->
    let v1, v2 = pair t1 t2 key v in
    Some (f v1 v2))
;;

let mapi2 t1 t2 ~f =
  Map.merge t1 t2 ~f:(fun ~key v ->
    let v1, v2 = pair t1 t2 key v in
    Some (f key v1 v2))
;;

let unzip t = Map.unzip t
let set t key data = Map.set t ~key ~data

module Sequence3 (A : Applicative.S3) = struct
  let sequence t =
    List.fold
      (Map.to_alist t)
      ~init:(A.return (Map.Using_comparator.empty ~comparator:(Map.comparator t)))
      ~f:(fun acc (key, data) ->
        A.map2 acc data ~f:(fun acc data -> Map.set acc ~key ~data))
  ;;
end

module Sequence2 (A : Applicative.S2) = Sequence3 (struct
    include A

    type ('a, 'b, _) t = ('a, 'b) A.t
  end)

module Sequence (A : Applicative) = Sequence2 (struct
    include A

    type ('a, _) t = 'a A.t
  end)

include struct
  open Map

  let combine_errors = combine_errors
  let data = data
  let for_all = for_all
  let for_alli = for_alli
  let iter = iter
  let iter_keys = iter_keys
  let iteri = iteri
  let map = map
  let mapi = mapi
  let fold = fold
  let fold_right = fold_right
  let to_alist = to_alist
  let validate = validate
  let validatei = validatei
end

module Make_plain_with_witnesses (Key : Key_plain_with_witnesses) = struct
  module Key = struct
    include Key
    include Comparable.Make_plain_using_comparator (Key)
  end

  type comparator_witness = Key.comparator_witness
  type enumeration_witness = Key.enumeration_witness
  type 'a t = 'a Key.Map.t [@@deriving sexp_of, compare, equal]

  let quickcheck_generator a_generator =
    let data = Quickcheck.Generator.list_with_length (List.length Key.all) a_generator in
    Quickcheck.Generator.map data ~f:(fun data ->
      List.zip_exn Key.all data |> Key.Map.of_alist_exn)
  ;;

  (* Dummy values; maybe we should make them do something someday? *)
  let quickcheck_shrinker _a_shrinker = Quickcheck.Shrinker.empty ()
  let quickcheck_observer _a_observer = Quickcheck.Observer.singleton ()

  let create f =
    List.fold Key.all ~init:Key.Map.empty ~f:(fun t key -> Map.set t ~key ~data:(f key))
    [@nontail]
  ;;

  let create_const x = create (fun _ -> x)

  let named_key_set : _ Set.Named.t =
    { set = Key.Set.of_list Key.all; name = "[Key.all]" }
  ;;

  let of_map map ~if_missing =
    create (fun key ->
      match Map.find map key with
      | Some value -> value
      | None -> if_missing ())
  ;;

  let of_map_exn map =
    Set.Named.equal named_key_set { set = Map.key_set map; name = "[Map.key_set map]" }
    |> ok_exn;
    of_map map ~if_missing:(fun () ->
      raise_s
        [%message
          "impossible: all keys must be present in the map as verified by the key set"])
  ;;

  let of_alist_exn alist = of_map_exn (Key.Map.of_alist_exn alist)
  let of_alist_multi_exn alist = of_map_exn (Key.Map.of_alist_multi alist)

  let of_alist_multi alist =
    of_map (Key.Map.of_alist_multi alist) ~if_missing:(fun () -> [])
  ;;

  include Applicative.Make (struct
      type nonrec 'a t = 'a t

      let return = create_const
      let apply t1 t2 = map2 t1 t2 ~f:(fun f x -> f x)
      let map = `Custom map
    end)
end

module Make_for_include_functor_plain_with_witnesses (Key : Key_plain_with_witnesses) =
struct
  module Total_map = Make_plain_with_witnesses (Key)
end

module Make_with_witnesses (Key : Key_with_witnesses) = struct
  module Key = struct
    include Key
    include Comparable.Make_binable_using_comparator (Key)
  end

  type 'a t = 'a Key.Map.t [@@deriving sexp, bin_io, compare, equal]

  include (
    Make_plain_with_witnesses
      (Key) :
        module type of Make_plain_with_witnesses (Key)
        with module Key := Key
        with type 'a t := 'a t)

  let t_of_sexp a_of_sexp sexp =
    let t = t_of_sexp a_of_sexp sexp in
    validate_map_from_serialization (module Key) t;
    t
  ;;

  include Bin_prot.Utils.Make_binable1_without_uuid [@alert "-legacy"] (struct
      type nonrec 'a t = 'a t

      module Binable = Key.Map

      let to_binable x = x

      let of_binable x =
        validate_map_from_serialization (module Key) x;
        x
      ;;
    end)
  end

module Make_for_include_functor_with_witnesses (Key : Key_with_witnesses) = struct
  module Total_map = Make_with_witnesses (Key)
end

module Make_plain (Key : Key_plain) = Make_plain_with_witnesses (struct
    include Key
    include Comparable.Make_plain (Key)
    include Enumeration.Make (Key)
  end)

module Make_for_include_functor_plain (Key : Key_plain) = struct
  module Total_map = Make_plain (Key)
end

module Make (Key : Key) = Make_with_witnesses (struct
    include Key
    include Comparable.Make_binable (Key)
    include Enumeration.Make (Key)
  end)

module Make_for_include_functor (Key : Key) = struct
  module Total_map = Make (Key)
end

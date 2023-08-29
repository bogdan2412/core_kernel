(** This module gives access to the same version/build information returned by
    [Command]-based executables when called with the [-version] or [-build-info] flags
    by [$0 version (-build-info | -version)] or [$0 (-build-info | -version)].

    Here's how it works: we arrange for the build system to, at link time, include an
    object file that defines symbols that version_util.ml uses to get the strings that
    contain the information that this module provides.  When building with OMake, our
    OMakeroot runs build_info.sh to generate *.build_info.c with the symbols and that is
    linked in.
*)

open! Core

(** All hg repos and their revision. *)
val version_list : string list

(** Like [version_list] but space separated. Consider using [version_list] instead. *)
val version : string

module Version : sig
  (** [t] is the structured representation of a single entry from [version_list]. *)
  type t =
    { repo : string
    ; version : string
    }
  [@@deriving sexp_of]

  (** Parse a single line of version-util. It's almost always better to use one of the
      functions below, because applying this to [Version_util.version] results in the
      following weird behaviors:

      - NO_VERSION_UTIL gets parsed { repo = "NO_VERSION"; version="UTIL" }
      - "repo1_rev1 repo2_rev2" gets parsed as { repo = "repo1_rev1 repo2"; version = "rev2" }
  *)
  val parse1 : string -> t Or_error.t

  (** In the following functions [Error _] means the format is unparsable, [Ok None] means
      the version is NO_VERSION_UTIL. *)

  val parse_list : string list -> t list option Or_error.t
  val parse_lines : string -> t list option Or_error.t
  val current_version : unit -> t list option

  (** The [_present] functions return [Error] instead of [None] when there's no version
      util. There is no version util during most builds. *)

  val parse_list_present : string list -> t list Or_error.t
  val parse_lines_present : string -> t list Or_error.t
  val current_version_present : unit -> t list Or_error.t
end

val arg_spec : (string * Arg.spec * string) list

(** [Application_specific_fields] is a single field in the build-info sexp that holds
    a [Sexp.t String.Map.t], which can be chosen by the application to hold custom
    fields that it needs. *)
module Application_specific_fields : sig
  type t = Sexp.t String.Map.t [@@deriving sexp]
end

(** Various additional information about the circumstances of the build: who built it,
    when, on what machine, etc.
    [build_info] is the information as it was generated by the build system.
    [reprint_build_info] parses and prints the string back, which alters a bit the layout
    and order of the fields but more importantly allows to display times in the current
    zone. *)
val build_info : string

val build_info_as_sexp : Sexp.t
val reprint_build_info : (Time_float.t -> Sexp.t) -> string
val username : string option
val hostname : string option
val kernel : string option
val build_time : Time_float.t option
val x_library_inlining : bool
val dynlinkable_code : bool
val compiled_for_speed : bool
val application_specific_fields : Application_specific_fields.t option
val ocaml_version : string
val allowed_projections : string list option

(** Relative to OMakeroot dir *)
val executable_path : string

val build_system : string
val with_fdo : (string * Md5.t option) option

module For_tests : sig
  val parse_generated_hg_version : string -> string list
end

(** If [false], all the variables above are filled in with bogus values.
    The value is [false] in tests at the moment. *)
val build_system_supports_version_util : bool

(** When you read the words "version util" below, try adding the word "info" to
    them: "version util info" makes a little more sense. *)
module Expert : sig
  (** Gets the version util if it exists.

      Since 2022-11, this function is guaranteed to be bidirectionally compatible
      if we ever change the version util format. We guarantee that:

      - New versions of this function will always be able to parse the version
        util out of all binaries built after 2022-11.

      - Versions of this function which are less than one month old will always
        be able to parse the version util out of new binaries. Older versions of
        this function may not be able to parse the version util out of new binaries.

      If you care about performance, consider using lib/fast_get_version_util_from_file.
      It is around 10-20x faster than this function, which can take a small number of
      seconds for several hundred megabyte binaries. *)
  val get_version_util : contents_of_exe:string -> string option

  (** Inserts the given version util into the executable text given. Returns None if this
      could not happen (maybe this is an executable that doesn't link in the current
      library).

      [None] means to remove the version util. The purpose is to make it possible to
      compare executables up to version util. *)
  val replace_version_util
    :  contents_of_exe:string
    -> Version.t list option
    -> string option

  (** Turns raw hg version info into the standard string list format that [version_list]
      returns. *)
  val parse_generated_hg_version : string -> string list

  module For_tests : sig
    val count_pattern_occurrences : contents_of_exe:string -> int
  end
end

module Private__For_version_util_async : sig
  val version_util_start_marker : string
  val parse_generated_hg_version : string -> string list
  val raw_text : Version.t list option -> string
end

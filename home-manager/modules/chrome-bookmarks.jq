# Builds a Chrome/Chromium "Bookmarks" bookmark_bar root from a flat list of
# {path, name, url} link entries (path is a "/"-separated folder breadcrumb;
# "" means directly on the bar). Invoked by renderChromeBookmarks in
# home-manager/modules/sops.nix.
#
# Inputs (via --argjson / --arg):
#   $links   - the flat link list, decoded from secrets/bookmarks.toml
#   $now_us  - current time as a Chrome/WebKit timestamp string (microseconds
#              since 1601-01-01), used for every date_added/date_modified
#
# IDs are derived deterministically from path/index rather than random, so
# re-running this on an unchanged bookmarks.toml produces byte-identical
# output.

def parent_path($p):
  ($p / "/") as $segs
  | if ($segs | length) <= 1 then "" else ($segs[0:-1] | join("/")) end;

def leaf_name($p): ($p / "/") | last;

# All folder paths that must exist: every non-empty prefix of every link's
# path. E.g. "Work/CICD" implies "Work" and "Work/CICD" both exist.
def folder_paths($links):
  [
    $links[]
    | .path
    | select(. != "")
    | (. / "/") as $segs
    | range(1; ($segs | length) + 1)
    | $segs[0:.]
    | join("/")
  ] | unique;

# Deterministic fake-but-well-formed GUID from an integer id.
def mkguid($id):
  ($id | tostring | ("000000000000" + .) | .[-12:]) as $tail
  | "bcbc0000-0000-4000-8000-" + $tail;

def link_node($now_us; $l):
  {
    id: ($l._id | tostring),
    guid: mkguid($l._id),
    name: $l.name,
    type: "url",
    url: $l.url,
    date_added: $now_us,
    date_last_used: "0"
  };

($links | folder_paths(.)) as $folder_paths
| ($folder_paths | to_entries | map({key: .value, value: (1000 + .key)}) | from_entries) as $folder_ids
| (1000 + ($folder_paths | length)) as $link_id_base
| ($links | to_entries | map(.value + {_id: ($link_id_base + .key)})) as $links_indexed
| def render($p):
    ([$folder_paths[] | select(parent_path(.) == $p)]) as $child_folders
    | ([$links_indexed[] | select(.path == $p)]) as $direct_links
    | {
        children: (
          ($child_folders | map(
            {
              id: ($folder_ids[.] | tostring),
              guid: mkguid($folder_ids[.]),
              name: leaf_name(.),
              type: "folder",
              date_added: $now_us,
              date_modified: $now_us
            } + render(.)
          ))
          + ($direct_links | map(link_node($now_us; .)))
        )
      };
  render("")

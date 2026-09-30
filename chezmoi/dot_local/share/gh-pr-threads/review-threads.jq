[
  .data.repository.pullRequest.reviewThreads.nodes[]
  | .comments.nodes[0] as $first
  | select((env.GH_PR_THREADS_ALL == "1") or (.isResolved | not))
  | select((env.GH_PR_THREADS_AUTHOR == "") or ($first.author.login == env.GH_PR_THREADS_AUTHOR))
  | {
      resolved: .isResolved,
      outdated: .isOutdated,
      path: .path,
      line: .line,
      author: ($first.author.login // "unknown"),
      body: ($first.body // ""),
      url: ($first.url // "")
    }
]

#!/usr/bin/env bash
# list-my-threads.sh — READ-ONLY. Print the current branch's PR review threads
# that are UNRESOLVED and authored by the authenticated user (self-review), as a
# JSON array the skill can iterate. Resolved state and thread node ids come only
# from GitHub's GraphQL API, so this uses graphql (REST can't see either).
#
# Usage: list-my-threads.sh
#
# Each element:
#   { threadId, path, line, isOutdated, firstCommentId, author,
#     comments: [ { author, body } ], url }
# threadId       — GraphQL node id, pass to resolveReviewThread.
# firstCommentId — REST databaseId of the thread's first comment; reply with
#                  `gh api .../pulls/<n>/comments -F in_reply_to=<firstCommentId>`.
set -euo pipefail

command -v gh >/dev/null 2>&1 || { echo "ERROR: gh not found." >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq not found (needed to filter threads)." >&2; exit 1; }

number=$(gh pr view --json number -q .number 2>/dev/null) || {
  echo "ERROR: no PR for the current branch (or gh not authenticated)." >&2; exit 1; }
nwo=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null) || {
  echo "ERROR: could not resolve owner/repo." >&2; exit 1; }
owner=${nwo%%/*}; name=${nwo##*/}
me=$(gh api user -q .login 2>/dev/null) || {
  echo "ERROR: could not resolve the authenticated user (gh api user)." >&2; exit 1; }

read -r -d '' Q <<'GRAPHQL' || true
query($owner:String!,$name:String!,$number:Int!){
  repository(owner:$owner,name:$name){
    pullRequest(number:$number){
      url
      reviewThreads(first:100){
        pageInfo{ hasNextPage }
        nodes{
          id
          isResolved
          isOutdated
          path
          line
          originalLine
          comments(first:50){
            nodes{ databaseId author{ login } body createdAt }
          }
        }
      }
    }
  }
}
GRAPHQL

raw=$(gh api graphql -f query="$Q" -f owner="$owner" -f name="$name" -F number="$number") || {
  echo "ERROR: GraphQL query failed." >&2; exit 1; }

if [[ "$(printf '%s' "$raw" | jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.hasNextPage')" == "true" ]]; then
  echo "WARN: more than 100 review threads; only the first 100 were fetched." >&2
fi

printf '%s' "$raw" | jq --arg me "$me" '
  ( .data.repository.pullRequest.url ) as $url
  | [ .data.repository.pullRequest.reviewThreads.nodes[]
      | select(.isResolved == false)
      | select((.comments.nodes[0].author.login // "") == $me)
      | { threadId: .id,
          path: .path,
          line: (.line // .originalLine),
          isOutdated: .isOutdated,
          firstCommentId: (.comments.nodes[0].databaseId),
          author: (.comments.nodes[0].author.login),
          comments: [ .comments.nodes[] | { author: (.author.login), body: .body } ],
          url: $url } ]'

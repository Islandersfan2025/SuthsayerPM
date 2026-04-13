const blueskyUri = args[0]
const marketId = args[1]

if (!blueskyUri) throw Error("missing blueskyUri")
if (!marketId) throw Error("missing marketId")

// Simplest possible behavior for now:
// return YES if the post exists, otherwise INVALID

const endpoint =
  `https://public.api.bsky.app/xrpc/app.bsky.feed.getPosts?uris=${encodeURIComponent(blueskyUri)}`

const response = await Functions.makeHttpRequest({
  url: endpoint,
  method: "GET",
  timeout: 9000,
  headers: { accept: "application/json" }
})

let outcome = 3 // Invalid by default

if (
  !response.error &&
  response.data &&
  Array.isArray(response.data.posts) &&
  response.data.posts.length > 0
) {
  outcome = 1 // Yes
}

const encoded = ethers.AbiCoder.defaultAbiCoder().encode(
  ["bytes32", "uint8"],
  [marketId, outcome]
)

return ethers.getBytes(encoded)
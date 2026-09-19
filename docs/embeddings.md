# Embeddings

The catalog stores a vector for each section, instructor and review. The
vectors let a person search by meaning instead of by exact words, and let the
API answer "what is like this one?".

## How it works

1. A model includes `Embeddable` and defines `embedding_text`, the sentence
   that stands for the record.
2. `BackfillEmbeddingsJob` finds the rows whose text has no vector, or whose
   text changed since the vector was made, and hands them to
   `GenerateEmbeddingsJob` in batches of 100.
3. `GenerateEmbeddingsJob` calls `EmbeddingService`, which sends the batch to
   OpenAI and returns one vector per text.
4. The vector and the SHA256 of the text go into the `embedding` and
   `embedding_digest` columns with `update_columns`. An embedding is derived
   data, so the write must not touch `updated_at` and must not mark a
   student's calendar for sync.

The backfill runs every night at 4:45am, after the catalog sync. Text that did
not change never reaches the API, so a second run costs one table scan.

| Model       | What the vector stands for                          |
| ----------- | --------------------------------------------------- |
| `Course`    | Subject, course number, title, schedule type, credits |
| `Faculty`   | Name, title, department, school                     |
| `RmpRating` | The review comment, with the course it is about     |

## Model

`text-embedding-3-small`, 1536 dimensions, cosine distance. The whole catalog
costs a few cents to embed. `EmbeddingService::MODEL` and `DIMENSIONS` are the
one place both the stored vectors and the query vectors read, so they cannot
drift apart.

Changing the model or the dimension count means a new migration for the column
width and a full re-embed. Old vectors are not comparable to new ones.

## Configuration

`OPENAI_API_KEY` turns the feature on. Without it `EmbeddingService.configured?`
is false, the jobs log and return, and search falls back to keyword matching.
The key lives in the `wit-calendar-env` agenix secret on alastor.

Search by meaning needs the key **and** the `semantic_search` Flipper flag. The
flag is global: turn it on for everybody, not per actor. Turn it off to stop
every query embedding at once, for example if the API bill surprises you. The
catalog then answers with keyword results, and no request fails.

## Postgres

The `vector` extension must be installed on the server.

- **Production**: `ghcr.io/witcodingclub/calendar-postgres:17-alpine`, built by
  `.github/workflows/postgres-image.yml` from `docker/postgres/Dockerfile`. It
  is the same `postgres:17-alpine` the server already ran, with pgvector added.
  A Debian image such as `pgvector/pgvector:pg17` would swap musl for glibc,
  which changes text collation and needs a `REINDEX` of every text index.
- **CI**: `pgvector/pgvector:pg17`. The test database is thrown away every run,
  so collation does not matter there.
- **Local**: `brew install pgvector` next to `postgresql@17`.

Each table has an HNSW index with `vector_cosine_ops`. HNSW answers approximate
nearest-neighbour queries; at catalog size the approximation is exact in
practice.

## Commands

```bash
# Queue everything that needs a vector
bin/rails embeddings:backfill

# One model, still through the queue
bin/rails 'embeddings:backfill[Course]'

# One model, right now, without the queue
bin/rails 'embeddings:run[Course]'

# How much is embedded
bin/rails embeddings:status
```

## Specs

WebMock blocks the OpenAI host, so specs stub the request:

```ruby
stub_request(:post, EmbeddingService::API_URL)
  .to_return(status: 200, body: file_fixture("openai/embeddings.json").read)
```

`spec/support/embeddings.rb` has helpers that build a fake response of the
right shape and that write vectors onto records without an HTTP call.

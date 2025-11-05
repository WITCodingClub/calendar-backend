# pgvector Embeddings for RateMyProfessor

## Overview

This project uses pgvector to store and search semantic embeddings of RateMyProfessor reviews. This enables:

- **Semantic search**: Find reviews by meaning, not just keywords
- **Similar professors**: Discover faculty with similar teaching styles
- **Teaching profile matching**: Match professors based on student feedback themes

## Database Schema

### RmpRating Embeddings
- **Column**: `rmp_ratings.embedding` (vector, 1536 dimensions)
- **Purpose**: Embedding of individual review comments
- **Index**: HNSW index for fast cosine similarity search

### Faculty Embeddings
- **Column**: `faculties.embedding` (vector, 1536 dimensions)
- **Purpose**: Aggregated embedding representing overall teaching profile
- **Index**: Will be added after embeddings are generated

## Model Methods

### RmpRating

```ruby
# Find similar reviews
rating.similar_ratings(limit: 10, distance: "cosine")

# Find similar reviews from other faculty
rating.similar_comments_other_faculties(limit: 10)

# Scope for ratings with embeddings
RmpRating.with_embeddings
```

### Faculty

```ruby
# Find similar faculty based on teaching profile
faculty.similar_faculty(limit: 10, distance: "cosine")

# Semantic search across all faculty
Faculty.semantic_search(query_embedding, limit: 10)

# Scope for faculty with embeddings
Faculty.with_embeddings
```

## Distance Metrics

Available distance metrics:
- `"cosine"` (default) - Best for text embeddings, normalized
- `"euclidean"` - Euclidean distance
- `"inner_product"` - Inner product (dot product)

## Generating Embeddings

Embeddings need to be generated using an embedding model (e.g., OpenAI's text-embedding-3-small, text-embedding-ada-002).

**Recommended dimensions**:
- OpenAI text-embedding-3-small: 1536
- OpenAI text-embedding-ada-002: 1536
- OpenAI text-embedding-3-large: 3072

### Example Implementation

You'll need to:

1. Create a job to generate embeddings for comments:
```ruby
class GenerateRmpEmbeddingsJob < ApplicationJob
  def perform(rmp_rating_id)
    rating = RmpRating.find(rmp_rating_id)
    return if rating.comment.blank?

    # Call your embedding service (e.g., OpenAI API)
    embedding = EmbeddingService.generate(rating.comment)
    rating.update(embedding: embedding)
  end
end
```

2. Create a job to generate aggregated faculty embeddings:
```ruby
class GenerateFacultyEmbeddingJob < ApplicationJob
  def perform(faculty_id)
    faculty = Faculty.find(faculty_id)
    comments = faculty.rmp_ratings.pluck(:comment).compact.join(" ")
    return if comments.blank?

    embedding = EmbeddingService.generate(comments)
    faculty.update(embedding: embedding)
  end
end
```

3. Add the index to faculties after embeddings are generated:
```ruby
# In a migration
add_index :faculties, :embedding, using: :hnsw, opclass: :vector_cosine_ops, algorithm: :concurrently
```

## Docker Setup

The project uses the official `pgvector/pgvector:0.8.1-pg17` Docker image which includes pgvector pre-installed.

### Development
The `docker-compose.yml` is configured with pgvector support:
```yaml
postgres:
  image: pgvector/pgvector:0.8.1-pg17
```

The `init-db.sh` script automatically enables the vector extension on database initialization.

### Production/Deployment
When deploying, ensure your PostgreSQL instance has pgvector installed:
- **Homebrew**: `brew install pgvector`
- **Linux**: Install from pgvector releases or package manager
- **Cloud providers**: Most major providers (RDS, Cloud SQL, etc.) support pgvector

## Use Cases

### 1. Similar Professor Recommendations
```ruby
faculty = Faculty.find(123)
similar = faculty.similar_faculty(limit: 5)
```

### 2. Find Reviews with Similar Themes
```ruby
rating = RmpRating.find(456)
similar_reviews = rating.similar_ratings(limit: 10)
```

### 3. Semantic Search (requires query embedding)
```ruby
query = "engaging professor who explains concepts clearly"
query_embedding = EmbeddingService.generate(query)
results = Faculty.semantic_search(query_embedding, limit: 10)
```

### 4. Cross-Faculty Review Analysis
```ruby
# Find reviews similar to this one, but from other professors
rating.similar_comments_other_faculties(limit: 10)
```

## Performance Considerations

- **HNSW indexes** provide excellent query performance but take longer to build
- Indexes are built **concurrently** to avoid blocking writes
- For large datasets, consider batch processing embedding generation
- Use background jobs for embedding generation to avoid blocking requests

## References

- [pgvector GitHub](https://github.com/pgvector/pgvector)
- [neighbor gem](https://github.com/ankane/neighbor) (provides `has_neighbors`)

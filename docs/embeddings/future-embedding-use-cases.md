# Future Embedding Use Cases

This document outlines potential use cases for vector embeddings and semantic search beyond the currently implemented systems (Faculty, RmpRating, and Course embeddings).

## High-Value Use Cases

### 1. User Learning Profiles

**Concept:** Aggregate data about a user's enrolled courses, preferences, and success patterns into a single embedding representing their learning profile.

**Benefits:**
- Match students with professors whose teaching style fits their learning preferences
- Recommend courses based on successful past enrollments
- Personalized academic advising suggesting optimal schedule combinations
- Identify struggling students early by comparing profiles to successful patterns

**Implementation Approach:**
```ruby
# Add to User model
class User < ApplicationRecord
  has_neighbors :learning_profile_embedding, dimensions: 1536

  def generate_learning_profile_embedding
    # Combine:
    # - Past course titles/subjects from enrollments
    # - RMP ratings of professors they chose
    # - Course difficulty levels they succeeded in
    # - Schedule patterns they prefer (morning/evening, MWF/TTh)
  end

  def similar_students(limit: 10)
    nearest_neighbors(:learning_profile_embedding, distance: "cosine")
      .limit(limit)
  end

  def recommended_courses_for_term(term)
    # Find similar students' successful enrollments
    # Exclude courses already taken
    # Filter by term availability
  end
end
```

**Data Sources:**
- Enrollment history
- Course selections across terms
- Faculty ratings/preferences
- Meeting time patterns
- Success indicators (if grades available)

---

### 2. Building & Room Context

**Concept:** Embed building and room characteristics to enable location-aware course discovery and schedule optimization.

**Benefits:**
- "Find courses in convenient locations" relative to student preferences
- Group courses by campus area to minimize walking time
- Identify similar classroom environments (lab vs lecture hall vs small seminar)
- Optimize campus navigation patterns

**Implementation Approach:**
```ruby
# Add to Building model
class Building < ApplicationRecord
  has_neighbors :embedding, dimensions: 1536

  def generate_embedding
    # Combine:
    # - Building name and abbreviation
    # - General location description (e.g., "north campus near parking lot C")
    # - Typical course types held here
    # - Amenities (computer lab, science equipment, etc.)
  end

  def nearby_buildings(limit: 5)
    nearest_neighbors(:embedding, distance: "cosine").limit(limit)
  end
end

# Add to Room model
class Room < ApplicationRecord
  has_neighbors :embedding, dimensions: 1536

  def generate_embedding
    # Combine:
    # - Room number and floor
    # - Building context
    # - Capacity and layout
    # - Equipment/features (projector, computers, lab equipment)
  end
end
```

**Data Sources:**
- Building names, abbreviations, locations
- Room capacities and floor numbers
- Course schedule types typically held in each location
- Physical campus layout data (if available)

---

### 3. Schedule Pattern Matching

**Concept:** Embed meeting time patterns to help students find schedules matching their preferences and lifestyle.

**Benefits:**
- Match courses to student schedule preferences (morning person vs night owl)
- Find optimal daily schedules minimizing gaps between classes
- Group similar schedule patterns (MWF mornings, TTh afternoons, etc.)
- Enable queries like "Find courses that meet similar times as my current schedule"

**Implementation Approach:**
```ruby
# Add to MeetingTime model
class MeetingTime < ApplicationRecord
  has_neighbors :pattern_embedding, dimensions: 1536

  def generate_pattern_embedding
    # Combine:
    # - Day pattern (e.g., "Monday Wednesday Friday")
    # - Time of day (morning/afternoon/evening)
    # - Duration and frequency
    # - Building location for context
  end

  def similar_schedules(limit: 10)
    nearest_neighbors(:pattern_embedding, distance: "cosine").limit(limit)
  end
end

# Could also create aggregate embeddings for entire course schedules
class Enrollment < ApplicationRecord
  def schedule_embedding
    # Aggregate all meeting times for enrolled courses
    # Represents student's complete weekly schedule pattern
  end
end
```

**Use Cases:**
- "Show me 4-credit courses with similar meeting patterns to my favorite class"
- "Find courses that won't conflict with my work schedule pattern"
- Schedule optimization: minimize campus travel by grouping nearby buildings

---

## Medium-Value Use Cases

### 4. TeacherRatingTag Analysis & Clustering

**Concept:** Use embeddings to understand relationships between RMP tags and automatically discover teaching style dimensions.

**Benefits:**
- Cluster similar tags ("engaging" ≈ "interesting" ≈ "fun")
- Discover hidden teaching style dimensions beyond RMP's predefined tags
- Cross-reference tags with actual comment content for validation
- Identify contradictory tag patterns (e.g., "easy" + "learned a lot")

**Implementation Approach:**
```ruby
# Add to TeacherRatingTag model
class TeacherRatingTag < ApplicationRecord
  has_neighbors :embedding, dimensions: 1536

  def generate_embedding
    # Embed the tag name
    # Could also incorporate context from comments where tag appears
  end

  def similar_tags(limit: 10)
    nearest_neighbors(:embedding, distance: "cosine").limit(limit)
  end

  def self.discover_tag_clusters(num_clusters: 5)
    # K-means or HDBSCAN clustering on tag embeddings
    # Group tags into semantic categories
  end
end

# Enhanced Faculty search
class Faculty < ApplicationRecord
  def find_by_teaching_style_description(description)
    # Embed user's natural language description
    # Match against faculty's aggregated tag embeddings
  end
end
```

**Analysis Opportunities:**
- Dimensionality reduction (t-SNE/UMAP) to visualize tag relationships
- Identify redundant tags that should be merged
- Discover new tag dimensions not captured by RMP

---

### 5. Historical Teaching Trends

**Concept:** Embed faculty rating patterns across time periods to track teaching evolution and stability.

**Benefits:**
- Identify professors who have improved significantly over time
- Find consistently high-quality instructors vs. variable ones
- Track how course difficulty or teaching style has changed
- Predict future performance based on trajectory

**Implementation Approach:**
```ruby
# Add to Faculty model
class Faculty < ApplicationRecord
  def rating_trajectory_embedding(window_months: 12)
    # Create embeddings for rating periods
    # Compare sequential periods to detect trends
  end

  def teaching_improvement_score
    # Compare early ratings vs recent ratings embeddings
    # Positive score = improved, negative = declined
  end

  def consistency_score
    # Variance in embeddings across time periods
    # Low variance = consistent, high variance = unpredictable
  end
end

# Could create TimeSeriesRating model
class RatingPeriod < ApplicationRecord
  belongs_to :faculty
  has_neighbors :period_embedding, dimensions: 1536

  # Stores aggregated embeddings for a time window
  # Enables temporal queries and trend analysis
end
```

**Queries Enabled:**
- "Show me professors who improved the most in the last 2 years"
- "Find instructors with stable, high ratings over time"
- "Which courses have become harder/easier over time?"

---

### 6. Cross-Faculty Teaching Style Discovery

**Concept:** Enhanced version of the existing `similar_faculty` functionality with more nuanced style matching.

**Benefits:**
- Find faculty teaching similar subjects but with different pedagogical approaches
- "Find another CS professor who emphasizes practical projects" (vs theory-heavy)
- Better recommendations than simple "related professors" from RMP
- Help students find alternative instructors matching specific preferences

**Implementation Approach:**
```ruby
# Enhance existing Faculty model
class Faculty < ApplicationRecord
  # Already has: has_neighbors :embedding, dimensions: 1536

  def similar_by_style(style_query, limit: 5, exclude_subject: false)
    # style_query examples:
    # - "engaging lecturer with lots of examples"
    # - "tough but fair, prepares you for real world"
    # - "very organized with clear expectations"

    # Generate embedding for style query
    # Find nearest neighbors
    # Optionally filter by subject similarity
  end

  def teaching_style_summary
    # Generate natural language summary from embeddings
    # Combine RMP ratings, tags, and comments
  end
end
```

**Advanced Features:**
- Style transfer: "Find instructors like Prof A but teaching Subject B"
- Negative examples: "Similar to Prof A but NOT like Prof B"
- Multi-dimensional style matching (difficulty, engagement, workload separately)

---

## Lower Priority / Research Use Cases

### 7. Term Schedule Planning Assistant

**Concept:** Embed entire term schedules (4-5 courses + constraints) to recommend optimal course combinations.

**Benefits:**
- Multi-course optimization considering all constraints
- "Suggest 4 courses for Spring 2025 that match my interests and avoid schedule conflicts"
- Balance workload, difficulty, and interests across semester
- Prevent overloading with too many difficult courses simultaneously

**Implementation Notes:**
- Complex optimization problem
- Would need student preference profiles, historical workload data
- Might be better solved with constraint satisfaction + embeddings hybrid

---

### 8. Faculty Hiring & Curriculum Planning Support

**Concept:** Use embeddings to identify gaps in departmental teaching coverage and inform hiring decisions.

**Benefits:**
- Identify teaching expertise gaps in department
- Find faculty with complementary (non-overlapping) skill sets
- Recommend new course offerings based on existing faculty strengths
- Support strategic academic planning

**Implementation Notes:**
- Requires administrative/department-level features
- Would need course catalog and departmental structure data
- More of a reporting/analytics feature than student-facing

---

### 9. Student Success Prediction

**Concept:** Predict student success likelihood in specific courses or with specific instructors.

**Benefits:**
- Academic advising: warn students about difficult combinations
- Recommend course/professor pairs with high success probability
- Early intervention for at-risk students
- Optimize course recommendations for retention

**Implementation Notes:**
- Requires outcome data (grades, completion rates)
- Privacy and ethical considerations
- Would need careful validation to avoid bias
- Regulatory compliance (FERPA) considerations

---

## Technical Implementation Considerations

### Embedding Generation Pipeline

All these use cases require a robust embedding generation system:

```ruby
# app/services/embedding_service.rb
class EmbeddingService
  def self.generate(text, model: "text-embedding-3-small")
    # Call OpenAI or other embedding API
    # Cache results to avoid redundant API calls
    # Handle rate limiting and errors
  end

  def self.batch_generate(texts, batch_size: 100)
    # Efficient batch processing
    # Use ActiveJob for large datasets
  end
end

# app/jobs/generate_embeddings_job.rb
class GenerateEmbeddingsJob < ApplicationJob
  queue_as :default

  def perform(model_class, record_id)
    record = model_class.find(record_id)
    embedding = EmbeddingService.generate(record.embedding_text)
    record.update(embedding: embedding)
  end
end
```

### Database Considerations

- **Index Strategy:** All embedding columns need HNSW indices (already established pattern)
- **Dimensions:** Consistent 1536 dimensions for OpenAI compatibility
- **Distance Metric:** Cosine similarity for most use cases
- **Performance:** HNSW provides sub-millisecond queries even with millions of vectors

### API Design

```ruby
# Example semantic search endpoint structure
# app/controllers/api/v1/semantic_search_controller.rb
class Api::V1::SemanticSearchController < ApplicationController
  def search
    # params: { query, type, limit, filters }
    case params[:type]
    when "courses"
      Course.semantic_search(query, params[:limit])
    when "faculty"
      Faculty.semantic_search(query, params[:limit])
    when "learning_profiles"
      User.find_similar_students(current_user, params[:limit])
    end
  end
end
```

---

## Priority Recommendations

### Implement Next (High ROI):
1. ✅ **Course embeddings** (DONE)
2. **User learning profiles** - High student value, leverages existing data
3. **Building/Room context** - Helps with schedule planning

### Implement Later (Medium ROI):
4. **Schedule pattern matching** - Useful but query patterns can handle much of this
5. **Tag clustering** - More of an analytics feature, less student-facing

### Research/Future (Lower Priority):
6. **Historical trends** - Interesting but requires time-series data accumulation
7. **Success prediction** - High value but complex (data, privacy, ethics)

---

## Related Documentation

- [pgvector Embeddings Implementation](./pgvector-embeddings.md) - Current implementation details
- Database schema: `db/schema.rb`
- Embedding-enabled models: `app/models/faculty.rb`, `app/models/rmp_rating.rb`, `app/models/course.rb`

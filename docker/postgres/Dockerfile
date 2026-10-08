# Postgres for production, with pgvector.
#
# The server keeps the same postgres:17-alpine base it has always run. A
# Debian-based image such as pgvector/pgvector:pg17 would swap musl for glibc,
# which changes text collation and needs a REINDEX of every text index. Adding
# the extension to the existing base avoids that.
#
# Built and pushed by .github/workflows/postgres-image.yml.
FROM postgres:17-alpine AS build

ARG PGVECTOR_VERSION=v0.8.6

RUN apk add --no-cache --virtual .build-deps build-base clang19 llvm19-dev llvm19 git \
    && git clone --branch "${PGVECTOR_VERSION}" --depth 1 https://github.com/pgvector/pgvector.git /tmp/pgvector \
    && cd /tmp/pgvector \
    && make OPTFLAGS="" \
    && make install \
    && rm -rf /tmp/pgvector \
    && apk del .build-deps

# The final image carries the extension files only, so the build tools do not
# ship to the server.
FROM postgres:17-alpine

COPY --from=build /usr/local/lib/postgresql/vector.so /usr/local/lib/postgresql/vector.so
COPY --from=build /usr/local/lib/postgresql/bitcode /usr/local/lib/postgresql/bitcode
COPY --from=build /usr/local/share/postgresql/extension/vector.control /usr/local/share/postgresql/extension/
COPY --from=build /usr/local/share/postgresql/extension/vector--*.sql /usr/local/share/postgresql/extension/

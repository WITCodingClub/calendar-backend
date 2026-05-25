.PHONY: frontend build dev

frontend:
	cd frontend && npm ci && npm run build

build: frontend
	bundle exec rails assets:precompile

dev:
	foreman start -f Procfile.dev

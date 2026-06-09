.PHONY: marketing build dev

marketing:
	cd marketing && npm ci && npm run build

build: marketing
	bundle exec rails assets:precompile

dev:
	foreman start -f Procfile.dev

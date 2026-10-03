.PHONY: run dev test

# Supabase settings come from the repo-root .env; without it the app falls back to demo mode.
# Release build: debug serves ~900 separate scripts (~180 MB), which makes the first load crawl.
run:
	cd app && flutter run -d web-server --web-port 8080 --release --dart-define-from-file=../.env

# Debug build with hot reload, slow first load.
dev:
	cd app && flutter run -d web-server --web-port 8080 --dart-define-from-file=../.env

test:
	cd app && flutter test
	supabase/tests/run.sh

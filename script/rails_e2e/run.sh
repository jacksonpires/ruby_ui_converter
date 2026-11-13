#!/usr/bin/env bash
# End-to-end compatibility check: generate a fresh Rails app, scaffold a
# resource (ERB) plus a second one with haml-rails (HAML), convert their views
# with ruby_ui_converter, wire the controllers
# to the generated Phlex/RubyUI classes and run an integration test that
# renders every converted view.
#
# Usage: script/rails_e2e/run.sh RAILS_SERIES [WORK_DIR]
#   RAILS_SERIES  e.g. 7.1, 7.2, 8.0, 8.1 (latest patch of that series is used)
#   WORK_DIR      where the throwaway app is created (default: a mktemp dir)
set -euo pipefail

RAILS_SERIES="${1:?usage: $0 RAILS_SERIES [WORK_DIR]}"
WORK_DIR="${2:-$(mktemp -d)}"
GEM_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HERE="$GEM_ROOT/script/rails_e2e"

echo "==> Ruby $(ruby -e 'print RUBY_VERSION'), Rails ~> $RAILS_SERIES.0, work dir $WORK_DIR"

gem install rails -v "~> $RAILS_SERIES.0" --no-document --conservative
RAILS_VERSION="$(ruby -e '
  series = Gem::Version.new(ARGV[0]).segments
  puts Gem::Specification.find_all_by_name("rails")
    .map(&:version).select { |v| v.segments[0, 2] == series }.max
' "$RAILS_SERIES")"
echo "==> Using Rails $RAILS_VERSION"

cd "$WORK_DIR"
rm -rf app_under_test
rails "_${RAILS_VERSION}_" new app_under_test --css=tailwind --skip-git --skip-docker \
  --skip-kamal --skip-thruster --skip-ci --skip-solid --quiet
cd app_under_test

# Older Rails series predate gems that `rails new` now resolves to and break
# Rails itself (unrelated to the converter): Rails < 8.1 calls JSON.generate
# with `quirks_mode`, removed in json 3; Rails 7.1's test runner is
# incompatible with minitest 6. Pin them so the check exercises the converter.
if ruby -e 'exit Gem::Version.new(ARGV[0]) < Gem::Version.new("8.1")' "$RAILS_SERIES"; then
  printf '\ngem "json", "< 3"\ngem "minitest", "< 6"\n' >> Gemfile
  bundle install
fi

bin/rails generate scaffold Category name:string --quiet
bin/rails generate scaffold Product name:string description:text price:decimal \
  quantity:integer rating:float active:boolean published_on:date \
  published_at:datetime metadata:json category:references --quiet
bin/rails db:migrate --quiet

# refract 1.1.0 (pulled in by phlex 2.4) references Prism::MissingNode, which
# prism 2.x removed — the app crashes as soon as it eager loads (production,
# or tests with CI set). Keep prism on 1.x until refract is fixed.
printf '\ngem "prism", "< 2"\n' >> Gemfile
bundle add phlex-rails
bin/rails generate phlex:install
bundle add ruby_ui
bin/rails generate ruby_ui:install
printf '\ngem "ruby_ui_converter", path: %s, group: :development\n' "\"$GEM_ROOT\"" >> Gemfile
bundle install

# Convert. No TTY on stdin, so the doctor only prints the missing prerequisites.
bundle exec ruby_ui_converter convert app/views/products --base-class "Views::Base" < /dev/null

# HAML: haml-rails ships scaffold templates for every Rails series checked
# here. Scaffold a second resource with them (tailwindcss-rails also registers
# a template engine, so pick haml explicitly) and convert its .haml views.
bundle add haml-rails
bin/rails generate scaffold Supplier name:string email:string active:boolean \
  --template-engine=haml --quiet
bin/rails db:migrate --quiet
ls app/views/suppliers/*.haml
bundle exec ruby_ui_converter convert app/views/suppliers --base-class "Views::Base" < /dev/null

for c in Link Button Input Checkbox Textarea Form Alert NativeSelect; do
  if grep -rqw "$c" app/views/products/*.rb app/views/suppliers/*.rb; then
    bin/rails generate ruby_ui:component "$c"
  fi
done

ruby "$HERE/patch_app.rb"
cp "$HERE/converted_views_test.rb" test/integration/
bin/rails tailwindcss:build
# CI=1 turns on eager loading in the test env, so every generated class is
# loaded (as in production), not only the ones the requests touch.
CI=1 bin/rails test test/integration/converted_views_test.rb

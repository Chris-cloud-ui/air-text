#!/usr/bin/env bash
set -o errexit

export RAILS_ENV=development
yarn install --check-files || true

bundle install
bundle exec rails assets:precompile
bundle exec rails assets:clean

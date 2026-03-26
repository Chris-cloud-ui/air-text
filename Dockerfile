# ------------------------------------------------------------------------------
# Base
# ------------------------------------------------------------------------------
FROM ruby:3.4.9 AS base
LABEL org.opencontainers.image.authors="contact@dxw.com"

# Install Node.js
ENV NODE_VERSION=24.14.0
ENV NODE_MAJOR_VERSION=${NODE_VERSION%%.*}
RUN curl -L https://deb.nodesource.com/setup_${NODE_MAJOR_VERSION}.x | bash -
RUN apt-get install -y nodejs=${NODE_VERSION}-1nodesource1

# Install Yarn
RUN curl -fsSL https://dl.yarnpkg.com/debian/pubkey.gpg | gpg --dearmor -o /usr/share/keyrings/yarn-archive-keyring.gpg
RUN echo "deb [signed-by=/usr/share/keyrings/yarn-archive-keyring.gpg] https://dl.yarnpkg.com/debian/ stable main" \
  | tee /etc/apt/sources.list.d/yarn.list

RUN apt-get update && apt-get install -y --no-install-recommends \
  build-essential \
  libpq-dev \
  yarn

ENV APP_HOME=/srv/app
ENV DEPS_HOME=/deps

# ------------------------------------------------------------------------------
# Dependencies
# ------------------------------------------------------------------------------
FROM base AS dependencies

WORKDIR ${DEPS_HOME}

# Install Ruby dependencies
COPY Gemfile Gemfile.lock ./
RUN gem update --system 3.5.1
RUN gem install bundler -v 2.4.7
RUN bundle config set frozen "true"
RUN bundle config set no-cache "true"
RUN bundle install --retry=10 --jobs=4

# Install JS dependencies (always include devDependencies)
COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile

# ------------------------------------------------------------------------------
# Web (build assets)
# ------------------------------------------------------------------------------
FROM base AS web

WORKDIR ${APP_HOME}

# Copy Ruby + JS dependencies
COPY --from=dependencies ${DEPS_HOME}/Gemfile ${APP_HOME}/Gemfile
COPY --from=dependencies ${DEPS_HOME}/Gemfile.lock ${APP_HOME}/Gemfile.lock
COPY --from=dependencies ${GEM_HOME} ${GEM_HOME}

COPY --from=dependencies ${DEPS_HOME}/package.json ${APP_HOME}/package.json
COPY --from=dependencies ${DEPS_HOME}/yarn.lock ${APP_HOME}/yarn.lock
COPY --from=dependencies ${DEPS_HOME}/node_modules ${APP_HOME}/node_modules

# Copy application code
COPY . ${APP_HOME}

# Ensure tmp dirs exist
RUN mkdir -p tmp/pids tmp/cache tmp/sockets log

# Build assets in development mode (avoids needing SECRET_KEY_BASE)
ENV RAILS_ENV=development
ENV NODE_ENV=development
RUN bundle exec rails dartsass:build && yarn build
# Precompile Rails assets
RUN bundle exec rails assets:precompile
# Switch to production for runtime
ENV RAILS_ENV=production
ENV NODE_ENV=production



# Entrypoint
COPY ./docker-entrypoint.sh /
RUN chmod +x /docker-entrypoint.sh
ENTRYPOINT ["/docker-entrypoint.sh"]

# Render will map PORT
EXPOSE 3000

CMD ["bundle", "exec", "rails", "server"]

# ------------------------------------------------------------------------------
# Test (optional)
# ------------------------------------------------------------------------------
FROM web AS test

RUN apt-get update && apt-get install -y \
  shellcheck \
  chromium-driver

COPY .rspec ${APP_HOME}/.rspec
COPY spec ${APP_HOME}/spec

# ------------------------------------------------------------------------------
# Base
# ------------------------------------------------------------------------------
FROM ruby:3.4.9@sha256:db06865ac42eb81d58a4338e2cb191666a563261325e7f6c90d97c15fab62f39 AS base
LABEL org.opencontainers.image.authors="contact@dxw.com"

# Specify the desired Node.js version
ENV NODE_VERSION=24.14.0
ENV NODE_MAJOR_VERSION=${NODE_VERSION%%.*}
RUN curl -L https://deb.nodesource.com/setup_${NODE_MAJOR_VERSION}.x | bash -
RUN apt-get install -y nodejs=${NODE_VERSION}-1nodesource1

RUN curl -fsSL https://dl.yarnpkg.com/debian/pubkey.gpg | gpg --dearmor -o /usr/share/keyrings/yarn-archive-keyring.gpg
RUN echo "deb [signed-by=/usr/share/keyrings/yarn-archive-keyring.gpg] https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list

RUN \
  apt-get update && \
  apt-get install -y --fix-missing --no-install-recommends \
  build-essential \
  libpq-dev

ENV APP_HOME=/srv/app
ENV DEPS_HOME=/deps

ARG RAILS_ENV
ENV RAILS_ENV=${RAILS_ENV:-production}
ENV NODE_ENV=${RAILS_ENV:-production}

# ------------------------------------------------------------------------------
# Dependencies
# ------------------------------------------------------------------------------
FROM base AS dependencies

RUN apt-get update && apt-get install -y yarn

WORKDIR ${DEPS_HOME}

# Install Ruby dependencies
ENV BUNDLE_GEM_GROUPS=${RAILS_ENV}

COPY Gemfile ${DEPS_HOME}/Gemfile
COPY Gemfile.lock ${DEPS_HOME}/Gemfile.lock

RUN gem update --system 3.5.1
RUN gem install bundler -v 2.4.7
RUN bundle config set frozen "true"
RUN bundle config set no-cache "true"
RUN bundle config set with "${BUNDLE_GEM_GROUPS}"
RUN bundle install --retry=10 --jobs=4
# End

# Install Javascript dependencies
COPY yarn.lock ${DEPS_HOME}/yarn.lock
COPY package.json ${DEPS_HOME}/package.json

RUN \
  if [ ${RAILS_ENV} = "production" ]; then \
  yarn install --frozen-lockfile --production; \
  else \
  yarn install --frozen-lockfile; \
  fi
# End

# ------------------------------------------------------------------------------
# Web
# ------------------------------------------------------------------------------
FROM base AS web

WORKDIR ${APP_HOME}

# Copy dependencies (relying on dependencies using the same base image as this)
COPY --from=dependencies ${DEPS_HOME}/Gemfile ${APP_HOME}/Gemfile
COPY --from=dependencies ${DEPS_HOME}/Gemfile.lock ${APP_HOME}/Gemfile.lock
COPY --from=dependencies ${GEM_HOME} ${GEM_HOME}

COPY --from=dependencies ${DEPS_HOME}/package.json ${APP_HOME}/package.json
COPY --from=dependencies ${DEPS_HOME}/yarn.lock ${APP_HOME}/yarn.lock
COPY --from=dependencies ${DEPS_HOME}/node_modules ${APP_HOME}/node_modules
# End

# Copy app code (sorted by vague frequency of change for caching)
RUN mkdir -p ${APP_HOME}/log
RUN mkdir -p ${APP_HOME}/tmp

COPY config.ru ${APP_HOME}/config.ru
COPY Rakefile ${APP_HOME}/Rakefile
COPY script ${APP_HOME}/script
COPY public ${APP_HOME}/public
COPY vendor ${APP_HOME}/vendor
COPY bin ${APP_HOME}/bin
COPY config ${APP_HOME}/config
COPY lib ${APP_HOME}/lib
COPY db ${APP_HOME}/db
COPY app ${APP_HOME}/app
# End

# Create tmp/pids
RUN mkdir -p tmp/pids

RUN \
  if [ "$RAILS_ENV" = "production" ]; then \
  SECRET_KEY_BASE="secret"; \
  fi

# TODO:
# In order to expose the current git sha & time of build in the /healthcheck
# endpoint, pass these values into your deployment script, for example:
# --build-arg CURRENT_GIT_SHA="$GITHUB_SHA" \
# --build-arg TIME_OF_BUILD="$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
ARG CURRENT_GIT_SHA
ARG TIME_OF_BUILD

ENV CURRENT_GIT_SHA=${CURRENT_GIT_SHA}
ENV TIME_OF_BUILD=${TIME_OF_BUILD}

COPY ./docker-entrypoint.sh /
RUN chmod +x /docker-entrypoint.sh
ENTRYPOINT ["/docker-entrypoint.sh"]

EXPOSE 3000

CMD ["bundle", "exec", "rails", "server"]

# ------------------------------------------------------------------------------
# Test
# ------------------------------------------------------------------------------
FROM web AS test

RUN \
  apt-get update && \
  apt-get install -y \
  shellcheck \
  chromium-driver \
  yarn
ENV RAILS_ENV=development
RUN bundle exec rails dartsass:build && yarn build
ENV RAILS_ENV=production
COPY eslint.config.mjs ${APP_HOME}/eslint.config.mjs
COPY .prettierignore ${APP_HOME}/.prettierignore
COPY .prettierrc ${APP_HOME}/.prettierrc
COPY .stylelintrc.json ${APP_HOME}/.stylelintrc.json
COPY .stylelintignore ${APP_HOME}/.stylelintignore

COPY .rspec ${APP_HOME}/.rspec
COPY spec ${APP_HOME}/spec

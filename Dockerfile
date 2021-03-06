# heavily borrowed from https://elixirforum.com/t/cannot-find-libtinfo-so-6-when-launching-elixir-app/24101/11?u=sigu
FROM elixir:1.11.2 AS app_builder

ARG env=prod

ENV LANG=C.UTF-8 \
   TERM=xterm \
   MIX_ENV=$env

RUN mkdir /opt/release
WORKDIR /opt/release

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs .
COPY mix.lock .
RUN mix deps.get && mix deps.compile

# Let's make sure we have node
RUN curl -sL https://deb.nodesource.com/setup_14.x | bash - && \
    apt-get install -y nodejs

# Compile assets
COPY assets ./assets
RUN npm install --prefix ./assets && \
    npm run deploy --prefix ./assets

# Now, let's go with the actual elixir code. The order matters: if we only
# change elixir code, all the above layers will be cached ~ less image build time.
COPY config ./config
COPY lib ./lib
COPY priv ./priv
COPY Makefile ./Makefile

RUN curl -L  https://github.com/CycloneDX/cyclonedx-cli/releases/download/v0.10.3/cyclonedx-linux-x64 --output cyclonedx-cli && chmod a+x cyclonedx-cli
RUN make sbom
RUN cp bom* ./assets/static

# Final build step: digest static assets and generate the release
RUN mix phx.digest && mix release

FROM debian:buster-slim AS app

RUN apt-get update && apt-get install -y openssl

RUN useradd --create-home app
WORKDIR /home/app
COPY --from=app_builder /opt/release/_build .
COPY entrypoint.sh .
RUN chmod a+x ./entrypoint.sh
RUN chown -R app: ./prod
USER app




CMD ["./entrypoint.sh"]

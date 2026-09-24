FROM caddy:2.11.4-alpine@sha256:6aeddd44c3078b0f9a35206472a11420648a79c184603ef95957d0a20044cb2b

RUN setcap -r /usr/bin/caddy \
    && addgroup -S caddy \
    && adduser -S -D -H -G caddy caddy \
    && chown caddy:caddy /data /config \
    && mkdir -p /srv/artifacts \
    && chmod 0555 /srv/artifacts

COPY --chmod=0444 Caddyfile /etc/caddy/Caddyfile
COPY --chmod=0444 scripts/club /srv/club
COPY --chmod=0444 artifacts/community-club-02e82f85ebcd9d0e7cb757f0906aea434a1b84b3.tar /srv/artifacts/community-club-02e82f85ebcd9d0e7cb757f0906aea434a1b84b3.tar

USER caddy

EXPOSE 8080

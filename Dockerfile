FROM caddy:2.11.4-alpine@sha256:6aeddd44c3078b0f9a35206472a11420648a79c184603ef95957d0a20044cb2b

RUN setcap -r /usr/bin/caddy \
    && addgroup -S caddy \
    && adduser -S -D -H -G caddy caddy \
    && chown caddy:caddy /data /config \
    && mkdir -p /srv/artifacts \
    && chmod 0555 /srv/artifacts

COPY --chmod=0444 Caddyfile /etc/caddy/Caddyfile
COPY --chmod=0444 scripts/club /srv/club
COPY --chmod=0444 artifacts/community-club-1ac31045e815d5b12569b34cbeaf53b97a7e81d0.tar /srv/artifacts/community-club-1ac31045e815d5b12569b34cbeaf53b97a7e81d0.tar

USER caddy

EXPOSE 8080

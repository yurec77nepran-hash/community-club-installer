# Обновление установщика

Репозиторий установщика и репозиторий приложения имеют независимые истории.
Commit и push выполняются только по отдельной просьбе владельца.

## Обновление распространяемой версии приложения

1. Выбрать проверенный commit приложения в локальном trusted clone и сначала
   создать временный candidate действующими значениями, не занимая будущий
   immutable path:

```bash
SOURCE_REPOSITORY=../community-club-source
COMMIT=<full-commit>
CANDIDATE="$(mktemp)"
trap 'rm -f "$CANDIDATE"' EXIT

git -C "$SOURCE_REPOSITORY" archive --format=tar \
  --prefix="community-club-$COMMIT/" "$COMMIT" >"$CANDIDATE"
stat -c %s "$CANDIDATE"
sha256sum "$CANDIDATE"
```

2. Зафиксировать полученные size/SHA-256 и одновременно заменить commit,
   archive URL/path, SHA-256 и size во всех
   контрактных местах:
   - `config/source.json`;
   - `scripts/club` и `scripts/generate-source-archive.sh`;
   - `Dockerfile`, `.dockerignore` и `Caddyfile`;
   - `tests/support/installer-test-support.sh`;
   - `tests/container-smoke.sh` и `tests/release-archive.test.sh`;
   - README и документы, если SHA указан явно.
3. После обновления контрактов создать final artifact только в отсутствующий
   immutable path валидирующим генератором:

```bash
FINAL="artifacts/community-club-$COMMIT.tar"
[[ ! -e "$FINAL" && ! -L "$FINAL" ]]
scripts/generate-source-archive.sh "$SOURCE_REPOSITORY" "$FINAL"
rm -f "$CANDIDATE"
trap - EXIT
```

Генератор требует точный commit, executable regular bootstrap blob, запрещает
symlink/submodule entries, root `.env`, `secrets` и installer marker, проверяет
ожидаемые size/SHA-256 и отказывается перезаписывать final path. Tracked
`garage.toml` остаётся допустимым source default.
4. Выполнить проверки:

```bash
bash -n scripts/club tests/installer.test.sh tests/support/installer-test-support.sh tests/cases/*.sh tests/container-smoke.sh
bash tests/installer.test.sh
bash tests/release-archive.test.sh
docker compose config
bash tests/container-smoke.sh
```

`tests/cases/source-contract.sh` автоматически сверяет `config/source.json`,
константы установщика, health-ответ Caddy, HTTP-only контейнерный контракт и
ожидания shell/container smoke.

5. Проверить, что diff не содержит секретов, credentials и mutable archive URL.
6. До production-публикации явно принять остаточный риск mutable app image tags
   либо отдельным изменением приложения зафиксировать образы по digest.
7. После отдельного разрешения создать commit и push в репозиторий установщика.
8. После отдельного разрешения обновить контейнер и проверить публичные
   `/health`, `/club` и точные bytes/hash/size archive route.

## Откат

Для отката вернуть предыдущий проверенный commit репозитория установщика и
пересобрать контейнер. Откат установщика не меняет host Caddy и уже развёрнутые
экземпляры Community Club.

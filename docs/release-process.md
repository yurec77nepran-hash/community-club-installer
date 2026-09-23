# Обновление установщика

Репозиторий установщика и репозиторий приложения имеют независимые истории.
Commit и push выполняются только по отдельной просьбе владельца.

## Обновление распространяемой версии приложения

1. Выбрать проверенный commit ветки приложения и получить его полный SHA.
2. Одновременно заменить repository/SHA во всех контрактных местах:
   - `config/source.json`;
   - `scripts/club`;
   - `Caddyfile` — поле `commit` ответа `/health`;
   - `tests/support/installer-test-support.sh`;
   - `tests/container-smoke.sh`;
   - README и документы, если SHA указан явно.
3. Выполнить проверки:

```bash
bash -n scripts/club tests/installer.test.sh tests/support/installer-test-support.sh tests/cases/*.sh tests/container-smoke.sh
bash tests/installer.test.sh
docker compose config
bash tests/container-smoke.sh
```

`tests/cases/source-contract.sh` автоматически сверяет `config/source.json`,
константы установщика, health-ответ Caddy, HTTP-only контейнерный контракт и
ожидания shell/container smoke.

4. Проверить, что diff не содержит секретов и произвольных source/ref overrides.
5. До production-публикации явно принять остаточный риск mutable app image tags
   либо отдельным изменением приложения зафиксировать образы по digest.
6. После отдельного разрешения создать commit и push в репозиторий установщика.
7. После отдельного разрешения обновить контейнер и проверить публичные
   `/health` и `/club`.

## Откат

Для отката вернуть предыдущий проверенный commit репозитория установщика и
пересобрать контейнер. Откат установщика не меняет host Caddy и уже развёрнутые
экземпляры Community Club.

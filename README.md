# Community Club Installer

Независимый публичный сервис установки Community Club. Контейнер отдаёт
Bash-скрипт и неизменяемый tar-архив исходников; сама установка выполняется на
целевом Ubuntu/Debian VPS.

Публичный HTTPS завершается в системном Caddy хоста. Контейнер принимает только
HTTP на внутреннем порту `8080`, а Compose публикует его исключительно на
`127.0.0.1:${HTTP_PORT:-3980}`. Поэтому сервис не конфликтует с занятыми host
Caddy портами `80/443`.

## Установка клуба

```bash
curl -fsSL https://shablon-clud.nepran-yuri.ru/club |
  DOMAIN=club.example.com ADMIN_EMAIL=owner@example.com bash
```

- Команду необходимо запускать из root-сессии на целевом VPS.
- `DOMAIN` — заранее направленный на VPS домен клуба.
- `ADMIN_EMAIL` — email первого владельца (`superadmin`).
- `INSTALL_EMAIL` не поддерживается.
- Проверок покупки, лицензии или доступа нет.

Установщик скачивает HTTPS-архив зафиксированного commit в новый приватный
staging, проверяет точный размер и SHA-256 до распаковки, заменяет только исходный
код в `/opt/community-club` и запускает штатный `scripts/server-bootstrap.sh` в
очищенном окружении. Git и доступ к приватному репозиторию на целевом VPS не
требуются. Существующие `.env`,
`secrets/` и `garage.toml` сохраняются. Пароль первого владельца выводится
bootstrap и сохраняется в:

```text
/opt/community-club/secrets/initial_admin_credentials
```

Повторная установка в непустую директорию разрешена только при наличии marker,
созданного этим установщиком. Symlink для target или сохраняемых runtime-файлов
отклоняется.

## Маршруты

- `GET /club` — Bash-установщик с `Content-Type: text/plain`.
- `GET /artifacts/community-club-1ac31045e815d5b12569b34cbeaf53b97a7e81d0.tar`
  — неизменяемый проверенный архив исходников.
- `GET /health` — JSON состояния сервиса и распространяемый commit.

## Локальная проверка

```bash
bash tests/installer.test.sh
bash tests/release-archive.test.sh
docker compose config
bash tests/container-smoke.sh
```

Production-копия установщика размещается в `/opt/community-club-installer`.
Host Caddy подключает snippet
`/etc/caddy/conf.d/community-club-installer.caddy` и проксирует
`shablon-clud.nepran-yuri.ru` на `127.0.0.1:3980`. Контейнер не управляет TLS,
ACME или сертификатами.

## Документация

- [Архитектурный контракт](docs/architecture-contract.md)
- [Эксплуатация](docs/operations.md)
- [Безопасность](docs/security.md)
- [Обновление релиза](docs/release-process.md)

GitHub-репозиторий, commit, push, DNS и deployment выполняются только по
отдельной явной команде владельца.

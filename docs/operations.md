# Эксплуатация

## Требования к серверу установщика

- Linux с Docker Engine и Docker Compose v2.
- Свободный loopback TCP-порт `127.0.0.1:3980`.
- DNS A-запись `shablon-clud.nepran-yuri.ru` на IP сервера.
- Системный Caddy, который владеет публичными портами `80/443` и импортирует
  `/etc/caddy/conf.d/*.caddy`.

Production-копия репозитория размещается в `/opt/community-club-installer`.
Контейнер принимает только HTTP на `8080`, а Compose публикует его только на
`127.0.0.1:${HTTP_PORT:-3980}`. Запуск после отдельного согласования deployment:

```bash
cd /opt/community-club-installer
docker compose up -d --build
docker compose ps
curl -fsS http://127.0.0.1:3980/health
curl -fsS https://shablon-clud.nepran-yuri.ru/health
curl -fsS https://shablon-clud.nepran-yuri.ru/club | bash -n
```

Контейнер автоматически перезапускается по политике `unless-stopped`. Он не
завершает TLS, не запускает ACME и не хранит сертификаты или другое состояние в
volumes.

## Поведение установки клуба

Установщик запускается из root-сессии, принимает только `DOMAIN` и
`ADMIN_EMAIL`, проверяет Ubuntu или Debian-like Linux и получает фиксированный
commit приложения в новый приватный staging. Git никогда не читает metadata или
worktree существующего `/opt/community-club`.

Непустой target принимается только с marker
`.community-club-installer`, созданным этим установщиком. При обновлении:

- старый source полностью заменяется содержимым проверенного staging;
- существующие `.env`, `secrets/`, `garage.toml` и marker не перезаписываются
  содержимым staging; при fresh install staged runtime defaults устанавливаются;
- marker и runtime-состояние сохраняются при ошибке копирования, поэтому запуск
  можно безопасно повторить;
- target и перечисленные runtime-артефакты не могут быть symlink;
- существующий target должен принадлежать root и не быть доступным на запись
  группе или остальным; marker должен принадлежать root и иметь mode `0600`;
- путь target остаётся прежним, поэтому имя Compose project и named volumes не
  меняются;
- bootstrap непосредственно перед root-запуском повторно проверяется на root
  ownership и отсутствие group/world write, получает очищенное окружение и
  возвращает вызывающему точный status.

Параллельные установки блокируются lock-файлом в root-owned каталоге
`/run/lock/community-club-installer` до полного завершения bootstrap.

## Host Caddy

Системный Caddy завершает публичный HTTPS и проксирует запросы в локальный
HTTP-сервис. Snippet `/etc/caddy/conf.d/community-club-installer.caddy`:

```caddyfile
shablon-clud.nepran-yuri.ru {
  reverse_proxy 127.0.0.1:3980
}
```

Такая схема не публикует контейнер наружу и не конфликтует с портами `80/443`,
которые уже занимает host Caddy.

## Диагностика

```bash
docker compose ps
docker compose logs --tail=200 community-club-installer
docker compose config
```

Остановка сервиса:

```bash
docker compose down
```

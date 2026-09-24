# Безопасность

## Граница доверия

Контейнер Caddy отдаёт `/club`, `/health` и один content-addressed архив. Он не
запускает установщик, не подключается к целевым VPS и не имеет доступа к Docker
socket или корню хоста.

Контейнер запускается:

- от непривилегированного пользователя `caddy`;
- с read-only root filesystem;
- без Linux capabilities;
- с `no-new-privileges`;
- с writable tmpfs только для `/tmp`;
- без volumes и привилегированных host mounts;
- с единственным HTTP-портом, опубликованным только на host loopback.

TLS, ACME и сертификаты находятся в границе системного Caddy хоста. Контейнер
установщика не имеет собственного TLS-состояния и недоступен напрямую извне.

## Защита источника

Публичный пользователь не может передать URL, branch или commit. Установщик
содержит фиксированные HTTPS URL, размер и SHA-256 архива полного commit. Каждый
запуск скачивает bytes в новый приватный staging, проверяет размер и SHA-256 до
распаковки, затем извлекает с `--strip-components=1`, `--no-same-owner` и
`--no-same-permissions`. Git на целевом VPS не требуется, а старые `.git/config`,
index и worktree не являются доверенными входами.

Release generator работает только с локальными Git-объектами точного commit,
не выполняет fetch и не использует credentials. До создания архива он запрещает
symlink/submodule entries, root `.env`, `secrets`, installer marker и требует
исполняемый обычный blob `scripts/server-bootstrap.sh`.

Существующий непустой target требует узнаваемый installer marker. `.env`,
`secrets/` и `garage.toml` рассматриваются только как filesystem runtime-state;
symlink target и сохраняемых артефактов отклоняется. Target и marker должны
принадлежать root; target не может быть group/world writable, а marker имеет mode
`0600`. Содержимое staging не перезаписывает существующие `.env`, `secrets/`,
`garage.toml` и marker. Bootstrap непосредственно перед root-запуском повторно
проверяется на root ownership и отсутствие group/world write, затем запускается
через `env -i`: caller-переменные `ADMIN_PASSWORD`, `COMPOSE_FILE`, `DOCKER_HOST`,
`BASH_ENV`, `ENV`, `CDPATH` и `GIT_*` ему не передаются.

В source archive отслеживается только runtime-default `garage.toml`. `.env`,
`secrets/` и installer marker в архив не входят; на fresh install их создают
bootstrap и установщик.

Email не является проверкой доступа. `ADMIN_EMAIL` используется только для
создания первого владельца клуба. Лицензирование и сбор аналитики отсутствуют.

## Секреты

В этом репозитории не должно быть `.env`, ключей, паролей и приватных
сертификатов. Первый пароль создаётся только на целевом VPS и хранится с
ограниченными правами в `/opt/community-club/secrets/initial_admin_credentials`.

Публичный shell-скрипт обладает теми же правами, с которыми пользователь его
запустил, и требует `root`. Перед обновлением опубликованного скрипта обязательны
тесты и просмотр diff. Привилегированный installer-контейнер не используется.

## Остаточный supply-chain риск

Проверенный архив не делает всю поставку неизменяемой: Compose приложения
использует mutable Docker image tags. Изменение app Dockerfiles/Compose находится
вне scope этого установщика. Этот риск необходимо явно принять либо отдельно
исправить pinning образов по digest до публикации production-установщика. Нельзя
считать текущую цепочку поставки полностью immutable.

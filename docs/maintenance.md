# Ручное обслуживание

Эта процедура применяется к еженедельному окну обслуживания и к критическому
security fix вне него. День и время выбирает оператор. Она не авторизует
подключение к VPS, перезагрузку, отправку Telegram или иное live-действие без
отдельного разрешения.

`make maintenance` — явственный ручной путь для обновления пакетов и повторного
применения конфигурации. Обычный `make apply` пакеты не обновляет. Нет
unattended updater или unattended rebooter: `make maintenance` не заменяет
ручное решение оператора о перезагрузке.

VPS ежедневно проверяет CRL через persistent systemd timer. За семь дней до
`nextUpdate` (или после пропущенного запуска) root-only service подписывает
новый 30-дневный CRL из текущих публичных issuance/revocation records и отдельно
проецируемого CA key. При отсутствии, неверных правах или несоответствии ключа
CA service записывает failure status и не открывает listener с невалидным CRL.
Обычный no-op не перезапускает VPN.

`make vpn-renew-open VPN_HOST=vpn.example` остаётся диагностическим ручным
запуском: он входит как `admin`, делает интерактивный `su` и запускает тот же
VPS service; CA key и controller authority в команду не передаются. Проверяйте
`systemctl status bastion-vpn-renew-crl.timer bastion-vpn-renew-crl.service` и
`/var/lib/bastion/vpn/crl-status.json`. Timer не заменяет ручное решение о
package updates или reboot.

## До применения

1. Для weekly maintenance и critical fix сначала проверьте изменения revision,
   `requirements.txt`, playbooks/roles и кандидаты пакетов/Ubuntu security
   notices. Запишите, какие package и automation dependency изменения одобрены.
2. До подключения к серверу выполните `make syntax`, `ansible-lint` и относящиеся к изменению
   focused component checks: как минимум `./tests/platform-static-test.sh`; при
   изменении VPN — `./tests/vpn-static-test.sh`, при изменении SSH notifications
   — `make ssh-notifications-test`, при изменении lifecycle —
   `python3 tests/device-lifecycle-test.py`. Исправьте локальные ошибки до
   activation.
3. Откройте административную SSH-сессию как `admin` и сохраните существующую SSH-сессию до конца
   процедуры. Не закрывайте существующую рабочую сессию, пока новый вход не
   подтверждён. Привилегированные действия продолжают использовать её
   password-authenticated `su` путь.

Эти syntax/static и synthetic component checks проверяют локальные контракты и не доказывают доступность live VPS, свежий SSH или работу VPN у клиента. Не
объявляйте readiness только по их успешному завершению.

## Применение и проверка

1. Из сохранённой административной сессии запустите `make maintenance` и
   сохраните его вывод вместе с review изменений и версий пакетов. Не запускайте
   одновременно второй apply или maintenance.
2. Проверяйте оба VPN отдельными protocol-compatible peers: OpenVPN и WireGuard
   должны устанавливать соединение и давать требуемый IPv4/IPv6 доступ. Для
   полного future live evidence используйте
   [VPN handoff checklist](../openspec/changes/implement-recovery-and-updates/vpn-live-checklist.md): он также охватывает forwarding, DNS и isolation.

Firewall role декларативно добавляет TCP/22, TCP/80, TCP/443, UDP/443 и
дополнительный TCP-порт `ansible_port` (по умолчанию `22`), затем один раз
включает UFW. До отдельно авторизованного live apply оператор проверяет
существующую UFW/static-firewall конфигурацию и удерживает административную
сессию. Роль не делает `ufw reset`, не мигрирует и не удаляет независимые
firewall resources; такие действия и rollback — отдельная операторская
процедура.

Если обновление требует reboot, только оператор вручную инициирует reboot в
согласованное окно из существующей административной сессии. После возврата
сервера проверьте SSH-доступ и обе VPN-проверки; лишь затем завершайте старую
SSH-сессию. Автоматический reboot не является частью этой процедуры.

## Ошибка или неполная проверка

Ansible и пакетные обновления не являются атомарной транзакцией: неудачное обслуживание могло уже частично изменить пакеты или конфигурацию. Сохраните
исходную SSH-сессию, вывод команды, выполненные шаги и непроверенные состояния;
устраните причину и повторите подходящую проверку или maintenance только после
нового review. Не объявляйте такой запуск успешным и не обещайте автоматический
rollback либо произвольный package downgrade. Потеря SSH-доступа или любой из
двух VPN-проверок также является failure, а не успешным rollout.

Локальные/synthetic checks и будущие live checks фиксируются раздельно. До
фактической отдельно авторизованной проверки VPS здесь нет evidence о remote
reachability, реальном reboot или пользовательских VPN-клиентах.

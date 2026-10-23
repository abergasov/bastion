# Запись ресурсов VPS

Изолированный QEMU/TCG fixture проверил foundation на 1 vCPU, 2 GB RAM и
20 GB qcow2 overlay. Это не заменяет будущий integration gate на VPS.

| Показатель | Наблюдение |
| --- | --- |
| RAM | 2,057,093,120 B total; во время package update available 1,616,371,712 B |
| Свободный диск | root FS 19,594,608,640 B; после update used 2,433,892,352 B (13%) |
| Throughput | не проверено |
| Swap | отсутствует |
| Непроверенные ограничения провайдера | public addressing, план/лимиты и live egress не проверены |

Целевой foundation — Ubuntu Server 26.04 LTS с Ansible. Ubuntu публикует минимум
1.5 GB RAM и 5 GB storage для Server; это не заменяет проверку Bastion на цели
1 vCPU / 2 GB / 20 GB. Initial/repeated apply, reboot и explicit package update
прошли в fixture; VPN throughput, provider networking и live-проверки остаются
не выполненными.

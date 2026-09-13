# Forkop-mod

[![Star](https://img.shields.io/github/stars/ushan0v/forkop?style=social)](https://github.com/ushan0v/forkop/stargazers)
[![Releases](https://img.shields.io/github/v/release/ushan0v/forkop?label=releases)](https://github.com/ushan0v/forkop/releases)
[![Telegram](https://img.shields.io/badge/Telegram-Forkop%20%7C%20Chat-2CA5E0?logo=telegram\&logoColor=white)](https://t.me/forkop_chat)
[![AI Assistant](https://img.shields.io/badge/Telegram-Forkop%20%7C%20AI%20Assistant-2CA5E0?logo=telegram\&logoColor=white)](https://t.me/forkop_aibot)

> **Forkop — это бывший Podkop Plus.** Проект переименован и продолжает развиваться как независимый форк [Podkop](https://github.com/itdoginfo/podkop).

### Установка

```sh
sh <(wget -O - https://raw.githubusercontent.com/Gavr1024/forkop/main/install.sh)
```

### Что нового в этом форке

* Поддержка подписок.
* Поддержка sing-box extended и транспорта XHTTP.
* Обновлённый LuCI-интерфейс.
* Расширенное управление секциями.
* Новые условия маршрутизации.
* Возможность поднять собственный VPN/proxy-сервер.
* Менеджер обновлений и установки компонентов.
* Встроенный мониторинг соединений.
* Расширенные настройки URLTest-групп.
* Автоматический выбор узла по приоритету.
* Каскадные подключения.
* Маршрутизация DNS-запросов через прокси.
* Резервные DNS-серверы.
* Отдельные DNS-серверы для выбранных доменов.
* Поддержка IPv6.
* Действие Bypass с полным обходом sing-box.
* Интеграция Zapret, Zapret2 и ByeDPI как отдельных действий секции.
* Dual-core: секция может идти через **sing-box** или **Xray**. Ядра работают одновременно; sing-box остаётся TPROXY/FakeIP, Xray подключается SOCKS-sidecar'ом и не ломает маршрутизацию.
* Установка и обновление Xray-core во вкладке «Компоненты», версия в «Системной информации», проверки в диагностике, вкладка «Ядра» в мониторинге (какой домен через какое ядро).
* Служба полностью переписана на ucode.
* Другие исправления и улучшения.

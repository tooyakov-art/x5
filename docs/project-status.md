# X5 — точка продолжения

Обновлено: 2026-09-07. Аудит клиентской приёмки в процессе.

- Использовать `work/x5-ios-payment-release`, ветку `codex/x5-ios-payments-239`.
- Базовый проверяемый commit `512f546`; iOS 1.1.9 (239) всё ещё WAITING_FOR_REVIEW.
- `work/x5` (9c98559) не соответствует отправленному бинарнику: не смешивать.
- Базовые 287 Python + 58/89 Deno-проверок прошли; полный UI ещё не пройден.
- Реестр сценариев/ограничений: [project-audit.md](project-audit.md).
- Никакие текущие изменения ещё не развёрнуты. Kaspi и новые уроки не включать.

## Следующие действия

1. Добавить воспроизводимый запуск реального UI в iPhone simulator и артефакты.
2. Проверить реальные auth/read-only запросы разрешённого App Review аккаунта,
   не раскрывая demo credentials и не выполняя покупки/генерации.
3. Запустить SQL-сценарии на отдельной базе X5, если схема восстанавливается
   из доступных миграций; чужие контейнеры/БД не использовать.
4. Воспроизвести независимые findings, исправить минимально и повторить тесты.
5. Актуализировать docs, записать итоговый commit/проверки/блокеры. Не менять
   заявку Apple до проверенного исправления клиентского кода.

## Команды исходной проверки

```powershell
& 'C:\Users\tuako\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' -m unittest discover -s scripts/tests -p 'test_*.py'
# В каждом из supabase/functions/verify-app-store-transaction и app-store-notifications:
deno test --frozen --allow-read
gh workflow run asc-release-audit.yml --ref codex/x5-full-fix-20260801 -f action=audit
```

Свежий ASC run: https://github.com/tooyakov-art/x5/actions/runs/34090679439

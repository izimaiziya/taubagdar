# TauBağdar — подготовка проекта одной командой.
# Запуск из этой папки в PowerShell:   powershell -ExecutionPolicy Bypass -File .\setup.ps1

Write-Host "1/5 Создаю платформу Android (существующие файлы не трогаются)..." -ForegroundColor Cyan
flutter create --org kz.taubagdar --project-name taubagdar --platforms android .

Write-Host "2/5 Убираю демо-тест Flutter..." -ForegroundColor Cyan
Remove-Item -ErrorAction SilentlyContinue test\widget_test.dart

Write-Host "3/5 Готовлю env.json..." -ForegroundColor Cyan
if (!(Test-Path env.json)) { Copy-Item env.example.json env.json; Write-Host "   Создан env.json — впишите в него ключ Groq." -ForegroundColor Yellow }
if (!(Test-Path .gitignore) -or !(Select-String -Path .gitignore -Pattern '^env\.json$' -Quiet)) { Add-Content .gitignore "`nenv.json" }

Write-Host "4/5 Скачиваю пакеты..." -ForegroundColor Cyan
flutter pub get

Write-Host "5/5 Проверяю код..." -ForegroundColor Cyan
flutter analyze

Write-Host ""
Write-Host "Готово. Запуск:  flutter run --dart-define-from-file=env.json" -ForegroundColor Green

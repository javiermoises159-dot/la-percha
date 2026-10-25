# La Percha (app Flutter)

Etapa 1: tema, logo, bienvenida, registro (con SMS simulado) y navegación.

- `lib/main.dart`: arranque y pantalla según la sesión
- `lib/welcome_screen.dart`: bienvenida
- `lib/auth_sheet.dart`: registro e inicio de sesión
- `lib/home_shell.dart`: navegación principal y perfil
- `lib/app_state.dart`: estado de la cuenta (se conectará a Firebase en la etapa 2)

La parte de Android (`android/`) no se guarda en el repositorio: GitHub la genera
al compilar (ver `.github/workflows/android.yml`).

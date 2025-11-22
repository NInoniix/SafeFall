# Fall Monitor - Fullstack (Frontend + Backend)

Proyecto de ejemplo para correr el **Monitor de Caídas** en React (Vite) + Backend Node.js (Express + WebSocket).

## Estructura
```
fall-monitor/
  frontend/        # Vite + React app (usa Tailwind via CDN para desarrollo)
  backend/         # Express + ws WebSocket server (simula datos y recibe alertas)
  README.md
```

## Requisitos
- Node.js 18+ y npm
- Visual Studio Code recomendado

## Instalación y ejecución (desde la terminal)

1. Backend:
```bash
cd fall-monitor/backend
npm install
npm run start
```
El servidor backend corre por defecto en `http://localhost:3001` y expone:
- WebSocket en `ws://localhost:3001`
- Endpoint POST `/api/emergency` que acepta JSON.

2. Frontend:
En otra terminal:
```bash
cd fall-monitor/frontend
npm install
npm run dev
```
Abre el navegador en la URL que Vite muestre (por defecto `http://localhost:5173`).

---

### Notas
- El frontend está configurado para conectarse al WebSocket `ws://localhost:3001`. Si cambias el puerto, modifica `config.serverUrl` y la llamada WebSocket en `src/App.jsx`.
- Para producción deberías configurar Tailwind correctamente, asegurar HTTPS y validación de números de teléfono, protección CSRF, etc.

---

Si quieres, puedo:
- Añadir autenticación básica al backend.
- Generar un `docker-compose.yml` para levantar frontend y backend con Docker.
- Adaptar para que el backend haga persistencia (SQLite / MongoDB).

Dime cuál de estas opciones quieres y lo genero.
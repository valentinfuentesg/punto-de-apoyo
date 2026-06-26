# 🇻🇪 Punto de Apoyo

> Mapa colaborativo de emergencia para Venezuela tras el sismo de 2026. Iniciativa ciudadana, sin fines de lucro.

🌐 **Producción**: [puntodeapoyovenezuela.com](https://www.puntodeapoyovenezuela.com/)
📨 **Contacto**: [@vxlentinF](https://twitter.com/vxlentinF)

---

## ¿Qué es?

Una aplicación web de **un solo archivo** (`index.html`) que muestra en un mapa:

- 🏥 **Hospitales** con conteo de pacientes registrados y badge "🩸 Buscan donantes" cuando aplica
- 📦 **Centros de acopio oficiales** geocoded de listados públicos
- 🟢 **Ofertas** ciudadanas (tengo agua, plantas eléctricas, transporte, etc.)
- 🟠 **Solicitudes** ciudadanas (necesito ayuda médica, transporte, suministros)
- 🚫 Zonas de peligro / rescate

Los usuarios pueden **reportar puntos anónimamente**, **confirmar** info verificada (👍), y **marcar como atendida** solicitudes ya cubiertas (con threshold de 2 confirmaciones).

## Stack

- **Frontend**: vanilla HTML + JavaScript, sin build, sin framework
- **Mapa**: Leaflet con tiles CartoDB Voyager
- **DB**: Supabase (PostgreSQL + Realtime + RLS)
- **Hosting**: Vercel (HTTPS, CDN global, analytics privacy-friendly)
- **Geocoding**: Nominatim (OpenStreetMap) con caché y diccionario hardcoded de hospitales VE

## Features

- 📍 Geolocalización automática + botón "ubicarme"
- 🔍 Buscador con autocompletado (Nominatim, priorizado a Venezuela)
- 🎓 Onboarding de 3 pasos solo la primera visita
- 👍 Sistema de confirmaciones por reporte (anti-doble-voto vía RPC)
- ✅ Marcar solicitudes como atendidas (requiere 2 confirmaciones distintas + nota obligatoria)
- 🩸 Badge "Buscan donantes" en hospitales que activamente solicitan sangre
- 🗺️ Mapa limitado a bounds de Venezuela (no se puede panear fuera)
- 🌑 Modo claro en tiles, UI oscura para ahorro de batería
- 📱 Responsive móvil, viewport dinámico (`100dvh`)
- 🔄 Realtime: reportes nuevos aparecen instantáneamente vía Supabase channels
- 🛡️ CSP estricto, X-Frame-Options DENY, sanitización de entradas, rate limit en DB

## Fuentes de datos integradas

| Fuente | Tipo | Frecuencia | Licencia / atribución |
|---|---|---|---|
| OpenStreetMap | Tiles + geocoding | — | © OpenStreetMap contributors (ODbL) |
| CartoDB Voyager | Map tiles | — | © CARTO |
| Google Sheets (centros) | Lista de centros de acopio | 5 min | Lista pública mantenida por la comunidad |
| Google Sheets (hospitales) | Conteo de pacientes | 15 min | Lista pública mantenida por la comunidad |
| [caracasayuda.com](https://caracasayuda.com) | Centros + reportes (Supabase) | 10 min | Iniciativa de Caracas Merch, atribución visible |
| [localizadosvenezuela.com](https://localizadosvenezuela.com) | Hospitales + conteo de localizados | On-load | MIT, por Giuseppe Gangi |

Toda la data integrada es **read-only** desde APIs públicas o sheets públicos. No copiamos a nuestra DB sin permiso. Si tu plataforma quiere integrarse o desintegrarse, abre un issue o contacta por X.

## Deploy

### Vercel (recomendado)

1. Fork este repo en GitHub
2. Conecta a Vercel (Workers & Pages → New project → Import repo)
3. Build settings: dejar todo vacío (HTML estático)
4. Output directory: `/`
5. Variables: ninguna requerida (las credenciales Supabase son anon, viven en `index.html`)
6. Deploy

HTTPS y CDN son automáticos. Geolocalización requiere HTTPS para funcionar — Vercel resuelve eso.

### Supabase

Corre `supabase_setup.sql` en el SQL Editor de tu proyecto. Es idempotente — crea tabla `reports`, RPCs `confirm_report` y `fulfill_report`, políticas RLS, rate limits, y constraints.

Asegúrate de:
1. Usar **solo la `anon` key** en el HTML (nunca `service_role`)
2. Configurar **Site URL** en Authentication → URL Configuration para tu dominio
3. Activar **Realtime** en la tabla `reports` para que los inserts se broadcast

## Privacidad

- **No hay cuentas, no pedimos email ni nombre.**
- Geolocalización ocurre solo en el navegador, nunca se envía.
- Reportes guardan solo: lat/lng, categoría, tipo, nota opcional, fecha. Sin PII.
- Huella anónima local (UUID en localStorage) solo para rate-limit y anti-doble-voto.
- Reportes ciudadanos se borran automáticamente a los 7 días vía RLS.
- Sin cookies de terceros. Vercel Analytics es privacy-friendly y first-party.

## Contribuir

Cualquier PR es bienvenido, especialmente:

- **Coordenadas de hospitales** que faltan en `HOSPITAL_COORDS` (busca en `index.html`)
- **Traducciones** o mejoras de copy
- **Bug fixes** o accesibilidad
- **Reportes de seguridad**: por DM en [@vxlentinF](https://twitter.com/vxlentinF), por favor no abras issue público

## License

[MIT](LICENSE) — usa, remix, modifica con atribución. Si construyes algo derivado, idealmente coordinar para no duplicar esfuerzos: hay muchas iniciativas hermanas y vale la pena que dialoguen.

## Créditos

Construido en colaboración con asistencia de IA (Claude). Inspirado y enriquecido por el trabajo de muchas comunidades:

- [caracasayuda.com](https://caracasayuda.com) (Caracas Merch)
- [localizadosvenezuela.com](https://localizadosvenezuela.com) (Giuseppe Gangi, [@ggangix](https://twitter.com/ggangix))
- [terremotovenezuela.app](https://terremotovenezuela.app) (Arturo Rios, [open source](https://github.com/ArturoRiosMock/mapa-emergencia-rescate))
- Comando ConVzla, Cáritas, Cruz Roja Venezolana, alcaldías, Voluntad Popular, Un Nuevo Tiempo, ONGs y miles de ciudadanos que mantienen los listados públicos.

🇻🇪 *La solidaridad es nuestra mayor fuerza.*

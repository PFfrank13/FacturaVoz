# Fase 24 · Revisión de producción y endurecimiento
- Supabase: publicado en Realtime clients, products, expenses, service_reminders, agent_tasks, recurring_invoices (20261119, aplicada).
- Seguridad: revocado EXECUTE de rls_auto_enable() a anon/authenticated (20261120).
- Rendimiento: 4 índices en FKs sin índice (20261120).
- Pendiente manual: activar "Leaked password protection" en Supabase Auth → Passwords.
- Pendiente opcional: unificar políticas duplicadas SELECT en coupons y promotions (aviso de rendimiento, no de seguridad).
- Vercel: sin errores desde el 25/10 (parse 404 por modelo retirado, ya corregido).

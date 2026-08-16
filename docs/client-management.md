# Gestión de clientes

Eliminar en la pantalla Clientes desactiva la configuración y elimina su plazo,
pero conserva la fila técnica de `billing_customers`. Esta decisión mantiene la
FK histórica `invoice_payment_terms -> billing_customers` en `ON DELETE RESTRICT`.
No se modifican facturas, filas mensuales, abonos, recibos ni recordatorios. El
marcador `configuration_active = false` evita que un `upsert` posterior redescubra
la configuración o reutilice el plazo eliminado.

Las acciones RPC reciben nombre y nombre comercial, los normalizan en el servidor
y añaden la organización obtenida con `require_current_organization_id()`. La
recuperación manual delega cada factura a `sync_enterprise_reminder`, por lo que
comparte elegibilidad, cálculo de fines de semana y unicidad con la automatización.

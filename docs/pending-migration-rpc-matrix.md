# Matriz de compatibilidad de migraciones pendientes

| RPC | Remoto actual | 20260903120000 | 20260903121000 | Final local | Flutter | Seguridad |
|---|---|---|---|---|---|---|
| `enterprise_import_monthly_invoices(uuid,int,int,jsonb)` | Importa vendedor/factura | Renombra la implementación y añade `payment_term_days` | Sin cambio | Una implementación explícita: vendedor, plazo individual e identidad de comprador | `SupabaseReportesService.importarFacturasMensualesAsignadas` | `SECURITY DEFINER`, `search_path=''`, sólo `authenticated` |
| `enterprise_save_report_row(uuid,int,text,text,text,text,date,numeric,text,numeric,jsonb,jsonb,jsonb,text)` | Guarda fila | Sin cambio | Valida que abonos no superen venta | Igual | `SupabaseReportesService.guardarFila` | `SECURITY DEFINER`, firma y grant ya existentes |
| `enterprise_upsert_invoice` | 7 argumentos | Sin cambio | Sin cambio | 9 argumentos; incorpora ID/tipo de comprador y elimina la sobrecarga anterior | `_guardarFacturaRpc` | `SECURITY DEFINER`, `search_path=''`, sólo `authenticated` |
| `list_customer_invoice_history(uuid,int,int,text,text,text)` | Agrupa por texto visible | Sin cambio | Sin cambio | Relaciona por `invoice_payment_terms.customer_id` | `CustomerHistoryRepository.load` | `SECURITY DEFINER`, `search_path=''`, sólo `authenticated` |
| `delete_enterprise_customer_configuration` | `(uuid,text,text)` | Sin cambio | Sin cambio | `(uuid,uuid)`; usa ID canónico | `CustomerTermsRepository.deleteCustomer` | `SECURITY DEFINER`, `search_path=''`, sólo `authenticated` |
| `schedule_enterprise_customer_pending` | `(uuid,text,text)` | Sin cambio | Sin cambio | `(uuid,uuid)`; usa ID canónico | `CustomerTermsRepository.schedulePending` | `SECURITY DEFINER`, `search_path=''`, sólo `authenticated` |
| `enterprise_save_payment_reminder(uuid,text,date,bool,bool,bool)` | Firma actual; lint detecta `result` ambiguo | Sin cambio | Sin cambio | Misma firma; variable y columna calificadas | `PaymentRemindersRepository` | `SECURITY DEFINER`, `search_path=''`, sólo `authenticated` |

Las migraciones de identidad no fusionan ningún cliente histórico. Una factura
futura con identificación sólo puede reclamar un perfil sin identificación si
hay exactamente una coincidencia por el par heredado nombre + nombre comercial.
Si hay cero o más de una coincidencia, se crea un perfil identificado separado.

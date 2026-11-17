-- Allow the owner/admin to save manual payment accounts and their own QR.
-- Privileges are column-scoped: mp_enabled cannot be forged from Flutter.
-- Existing RLS pay_settings_insert/update restrict writes to org admins.
begin;
grant insert(org_id, yape_phone, plin_phone, bank_name, bank_account,
  bank_cci, account_holder, pay_note, reminders_enabled, reminder_offsets,
  updated_at, yape_qr_path, plin_qr_path)
on public.org_pay_settings to authenticated;
grant update(yape_phone, plin_phone, bank_name, bank_account,
  bank_cci, account_holder, pay_note, reminders_enabled, reminder_offsets,
  updated_at, yape_qr_path, plin_qr_path)
on public.org_pay_settings to authenticated;
commit;

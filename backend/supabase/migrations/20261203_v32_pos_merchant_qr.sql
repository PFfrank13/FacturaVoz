-- The QR is supplied by the merchant; never generate a bank QR from a phone number.
begin;
alter table public.org_pay_settings
  add column if not exists yape_qr_path text,
  add column if not exists plin_qr_path text;
comment on column public.org_pay_settings.yape_qr_path is 'Private Supabase Storage path of merchant-provided Yape QR';
comment on column public.org_pay_settings.plin_qr_path is 'Private Supabase Storage path of merchant-provided Plin QR';
commit;
notify pgrst, 'reload schema';
